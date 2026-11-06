SET ROLE hafbe_owner;

/*
 * process_witness_votes: Processes witness votes, proxies, and expired accounts.
 *
 * Core operations: Handles account_witness_vote, account_witness_proxy,
 * proxy_cleared, declined_voting_rights, and expired_account_notification operations.
 *
 * Updates tables:
 *   - hafbe_app.witness_votes_history: Complete vote change history
 *   - hafbe_app.current_witness_votes: Current active witness votes
 *   - hafbe_app.account_proxies_history: Complete proxy change history
 *   - hafbe_app.current_account_proxies: Current proxy assignments
 *
 * WHY ROW-BY-ROW PROCESSING (not batch):
 *   Operations have complex interdependencies that require sequential processing:
 *
 *   1. Setting a proxy DELETES all existing witness votes for that account
 *   2. Clearing a proxy allows the account to vote directly again
 *   3. Expired/declined accounts lose ALL votes and proxies
 *
 *   Example sequence that MUST be processed in order:
 *     Op 100: Vote for witness A
 *     Op 200: Set proxy to X (cascade: deletes vote for A)
 *     Op 300: Clear proxy
 *     Op 400: Vote for witness B
 *
 *   Correct final state: Only vote for B exists
 *
 *   If processed as batch (all votes, then all proxies):
 *     - Section 1: Insert votes for A and B
 *     - Section 2: Set proxy (deletes ALL votes including B!)
 *     - Wrong final state: No votes
 *
 *   Therefore, operations MUST be processed in operation_id order.
 */
CREATE OR REPLACE FUNCTION hafbe_app.process_witness_votes(_from INT, _to INT)
RETURNS VOID
LANGUAGE plpgsql VOLATILE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
AS $$
DECLARE
  -- Cache operation type IDs to avoid repeated function calls
  _op_account_witness_vote         INT := hafbe_backend.op_account_witness_vote();
  _op_account_witness_proxy        INT := hafbe_backend.op_account_witness_proxy();
  _op_proxy_cleared                INT := hafbe_backend.op_proxy_cleared();
  _op_declined_voting_rights       INT := hafbe_backend.op_declined_voting_rights();
  _op_expired_account_notification INT := hafbe_backend.op_expired_account_notification();
  _result                          INT;
BEGIN

  /*
   * ===================================================================================
   * Main Processing Loop
   * ===================================================================================
   * Fetch all relevant operations in the block range and process them IN ORDER.
   *
   * The ORDER BY bc.id is CRITICAL - it ensures operations are processed in the
   * sequence they occurred on the blockchain, preserving the correct cascading
   * effects between votes and proxies.
   *
   * Each operation type is dispatched to its specialized handler function:
   *   - account_witness_vote      -> process_vote_op()
   *   - account_witness_proxy     -> process_proxy_ops(..., TRUE)
   *   - proxy_cleared             -> process_proxy_ops(..., FALSE)
   *   - declined_voting_rights    -> process_expired_accounts()
   *   - expired_account_notification -> process_expired_accounts()
   *
   * The handler functions are VOLATILE and perform DML (INSERT/UPDATE/DELETE).
   * They are called via a CASE expression in SELECT, which processes each row.
   */
  WITH proxy_ops AS MATERIALIZED (
    SELECT
      ov.body_value AS body,
      ov.id         AS id,
      ov.block_num,
      ov.op_type_id AS op_type
    FROM hafbe_app.operations_view ov
    WHERE ov.op_type_id IN (
      _op_account_witness_vote,
      _op_account_witness_proxy,
      _op_proxy_cleared,
      _op_declined_voting_rights,
      _op_expired_account_notification
    )
    AND ov.block_num BETWEEN _from AND _to
    AND ov.id >= hafd.operation_id(_from, 0)
    AND ov.id < hafd.operation_id(_to + 1, 0)
  ),

  /*
   * Process each operation by dispatching to the appropriate handler.
   *
   * IMPORTANT: The ORDER BY id ensures operations are processed sequentially
   * in the order they appeared on the blockchain.
   */
  balance_change AS (
    SELECT
      bc.id,
      (
        CASE
          WHEN bc.op_type = _op_account_witness_vote THEN
            hafbe_backend.process_vote_op(bc.body, bc.id)

          WHEN bc.op_type = _op_account_witness_proxy THEN
            hafbe_backend.process_proxy_ops(bc.body, bc.id, TRUE)

          WHEN bc.op_type = _op_proxy_cleared THEN
            hafbe_backend.process_proxy_ops(bc.body, bc.id, FALSE)

          WHEN bc.op_type = _op_declined_voting_rights
            OR bc.op_type = _op_expired_account_notification THEN
            hafbe_backend.process_expired_accounts(bc.body, bc.id)
        END
      ) AS result
    FROM proxy_ops bc
    ORDER BY bc.id
  )

  /*
   * Force evaluation of all rows (and thus all handler function calls)
   * by counting the results.
   */
  SELECT COUNT(*) FROM balance_change INTO _result;

END
$$;


/*
 * ===================================================================================
 * Witness vote caches
 * ===================================================================================
 * PURPOSE: Keep the cached witness vote statistics the API reads up to date.
 *
 * CACHE TABLES:
 *   - account_vest_stats_cache: Vesting power per account (own + proxied),
 *       covering current voters/proxies/proposal voters plus anyone with a
 *       witness vote event in today's window (issue #142)
 *   - witness_votes_cache: Total votes and voter count per witness
 *   - witness_rank_cache: Witness rankings by vote weight
 *   - witness_votes_change_cache: Daily vote changes (for "24h change" stats)
 *
 * Two entry points:
 *   - process_witness_votes_cache() recomputes all four caches in full. It is what
 *     the first LIVE iteration, CI and the mock setup call.
 *   - process_witness_votes_cache(_block) is what single_processing() calls for
 *     every LIVE block. It updates the caches incrementally from the block's
 *     impacted accounts and falls back to the full recompute whenever the block
 *     can change the set of tracked accounts, votes or witnesses, or is not the
 *     direct successor of the last block it refreshed (see that function).
 *
 * Every refresh is applied so that only rows whose values actually change are
 * written (plus inserts for new keys and deletes for keys that left the source
 * set). Rewriting every row every block produced ~4.9 MB of WAL per block and
 * ~25k dead tuples per block; whenever anything held an old snapshot (a long API
 * query, pg_dump, CREATE INDEX CONCURRENTLY) those dead tuples could not be
 * vacuumed, the tables bloated without bound, and the per-block refresh slowed
 * linearly until block processing fell behind.
 * MERGE ... WHEN NOT MATCHED BY SOURCE requires PostgreSQL 17+, HAF's floor.
 * Statement ORDER matters: caches 2-4 read cache 1 (and 3 reads 2) as refreshed
 * earlier in this same transaction.
 */

/*
 * witness_votes_cache_window_start: lower bound of the "daily change" window.
 *
 * Strictly this is the LAST block at or before today's midnight -- i.e. usually the
 * final block of yesterday -- and the window is inclusive of it, so one pre-midnight
 * block counts as today. That off-by-one is pre-existing behaviour, preserved
 * deliberately; correcting it moves published numbers and belongs in its own change.
 *
 * Ordered by created_at, not num: block timestamps rise strictly with the block
 * number, so both pick the same block, but only created_at lets
 * hive_blocks_created_at_idx find it with one descent. Ordered by num, the scan walks
 * pk_hive_blocks backwards over every block produced since midnight.
 *
 * CURRENT_DATE, not 'today'::DATE: the latter is a literal cast, folded to a constant
 * at PLAN time, so a cached plan would freeze the window at the day it was built.
 */
CREATE OR REPLACE FUNCTION hafbe_app.witness_votes_cache_window_start()
RETURNS INT
LANGUAGE sql STABLE
AS $$
  SELECT num
  FROM hive.blocks_view
  WHERE created_at <= CURRENT_DATE
  ORDER BY created_at DESC
  LIMIT 1
$$;


/*
 * refresh_witness_rank_cache: Cache 3, recomputed in full.
 *
 * Ranking criteria (in order):
 *   1. Total votes (DESC)
 *   2. Number of voters (DESC)
 *   3. Witness ID (DESC) - tiebreaker
 */
CREATE OR REPLACE FUNCTION hafbe_app.refresh_witness_rank_cache()
RETURNS VOID
LANGUAGE plpgsql VOLATILE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
AS $$
BEGIN
  MERGE INTO hafbe_app.witness_rank_cache t
  USING (
    SELECT
      cw.witness_id,
      (ROW_NUMBER() OVER (
        ORDER BY
          COALESCE(wv.votes, 0) DESC,
          COALESCE(wv.voters_num, 0) DESC,
          cw.witness_id DESC
      ))::INT AS rank
    FROM hafbe_app.current_witnesses cw
    LEFT JOIN hafbe_app.witness_votes_cache wv ON wv.witness_id = cw.witness_id
  ) s ON t.witness_id = s.witness_id
  WHEN MATCHED AND t.rank IS DISTINCT FROM s.rank THEN
    UPDATE SET rank = s.rank
  WHEN NOT MATCHED THEN
    INSERT (witness_id, rank) VALUES (s.witness_id, s.rank)
  WHEN NOT MATCHED BY SOURCE THEN DELETE;
END
$$;


/*
 * refresh_witness_votes_change_cache: Cache 4, recomputed in full.
 *
 * The change in votes and voters for each witness since the start of today, used
 * for "24h change" statistics in the API:
 *   - Positive vests for approve=TRUE votes
 *   - Negative vests for approve=FALSE votes
 *   - Sum gives net change in vote weight
 *
 * Recomputed on every block, incremental or not: it multiplies today's vote events
 * by the voters' CURRENT vests, so it changes whenever Cache 1 does, and it reads
 * only today's slice of witness_votes_history.
 *
 * The INNER JOIN is safe ONLY because Cache 1 was built with this same
 * _first_block_num -- see the fourth tracked_accounts branch in
 * hafbe_backend.account_vest_stats() (issue #142). Narrowing it re-opens the bug.
 *
 * Filtering source_op rather than the decoded block number keeps the predicate
 * sargable: hafd.operation_id(b, 0) is the minimum operation id in block b, so
 * this is exactly equivalent to source_op_block >= _first_block_num -- EXCEPT for
 * NULL, which is why the guard is explicit. hafd.operation_id is non-STRICT and
 * reads a NULL block number as 0, so without it a NULL window would aggregate all
 * of history rather than nothing.
 */
CREATE OR REPLACE FUNCTION hafbe_app.refresh_witness_votes_change_cache(_first_block_num INT)
RETURNS VOID
LANGUAGE plpgsql VOLATILE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
AS $$
BEGIN
  MERGE INTO hafbe_app.witness_votes_change_cache t
  USING (
    SELECT
      wvhc.witness_id,
      SUM(CASE WHEN wvhc.approve THEN avs.vests ELSE -1 * avs.vests END)::BIGINT AS votes_daily_change,
      SUM(CASE WHEN wvhc.approve THEN 1 ELSE -1 END)::INT                        AS voters_num_daily_change
    FROM hafbe_backend.witness_votes_history_view wvhc
    JOIN hafbe_app.account_vest_stats_cache avs ON avs.account_id = wvhc.voter_id
    WHERE _first_block_num IS NOT NULL
      AND wvhc.source_op >= hafd.operation_id(_first_block_num, 0)
    GROUP BY wvhc.witness_id
  ) s ON t.witness_id = s.witness_id
  WHEN MATCHED AND (t.votes_daily_change, t.voters_num_daily_change)
       IS DISTINCT FROM (s.votes_daily_change, s.voters_num_daily_change) THEN
    UPDATE SET votes_daily_change = s.votes_daily_change,
               voters_num_daily_change = s.voters_num_daily_change
  WHEN NOT MATCHED THEN
    INSERT (witness_id, votes_daily_change, voters_num_daily_change)
    VALUES (s.witness_id, s.votes_daily_change, s.voters_num_daily_change)
  WHEN NOT MATCHED BY SOURCE THEN DELETE;
END
$$;


/*
 * refresh_witness_votes_cache_full: all four caches recomputed in full.
 *
 * _first_block_num is the daily-change window (witness_votes_cache_window_start()).
 */
CREATE OR REPLACE FUNCTION hafbe_app.refresh_witness_votes_cache_full(_first_block_num INT)
RETURNS VOID
LANGUAGE plpgsql VOLATILE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
AS $$
BEGIN

  /*
   * ===================================================================================
   * Cache 1: Account Vest Stats
   * ===================================================================================
   * Caches vesting power statistics for each account:
   *   - vests: Total effective vesting power (own + proxied to this account)
   *   - account_vests: Account's own vesting power
   *   - proxied_vests: Vesting power proxied to this account by others
   *
   * _first_block_num is passed so the account set also covers voters with a vote
   * event inside today's window, including those who have just stopped being
   * current voters. That is what makes Cache 4's INNER JOIN lossless (issue #142);
   * the two must share one window or they can drift apart.
   */
  MERGE INTO hafbe_app.account_vest_stats_cache t
  USING (
    SELECT
      account_id,
      vests,
      account_vests,
      proxied_vests
    FROM hafbe_backend.account_vest_stats(_first_block_num)
  ) s ON t.account_id = s.account_id
  WHEN MATCHED AND (t.vests, t.account_vests, t.proxied_vests)
       IS DISTINCT FROM (s.vests, s.account_vests, s.proxied_vests) THEN
    UPDATE SET vests = s.vests, account_vests = s.account_vests, proxied_vests = s.proxied_vests
  WHEN NOT MATCHED THEN
    INSERT (account_id, vests, account_vests, proxied_vests)
    VALUES (s.account_id, s.vests, s.account_vests, s.proxied_vests)
  WHEN NOT MATCHED BY SOURCE THEN DELETE;


  /*
   * ===================================================================================
   * Cache 2: Witness Votes
   * ===================================================================================
   * Caches total vote weight and voter count per witness.
   * Uses the account_vest_stats_cache we just populated.
   *
   * The INNER JOIN below is deliberate and provably total — do NOT "fix" it to
   * match Cache 4 (issue #142). It is driven by current_witness_votes, which is
   * exactly the set hafbe_backend.witness_voters_list_view aggregates and hence
   * the first branch of tracked_accounts, so every driver key is a cache key.
   * Cache 1 populated that cache in this same statement sequence, in the same
   * transaction, with no intervening DML on current_witness_votes. Cache 4 is
   * the one that lacks this property: it is driven by HISTORY, a strict superset.
   * Same reasoning covers hafbe_backend.get_witness_voters.
   */
  MERGE INTO hafbe_app.witness_votes_cache t
  USING (
    SELECT
      cwv.witness_id,
      SUM(avs.vests)::BIGINT AS votes,
      COUNT(*)::INT          AS voters_num
    FROM hafbe_backend.current_witness_votes_view cwv
    JOIN hafbe_app.account_vest_stats_cache avs ON avs.account_id = cwv.voter_id
    GROUP BY cwv.witness_id
  ) s ON t.witness_id = s.witness_id
  WHEN MATCHED AND (t.votes, t.voters_num) IS DISTINCT FROM (s.votes, s.voters_num) THEN
    UPDATE SET votes = s.votes, voters_num = s.voters_num
  WHEN NOT MATCHED THEN
    INSERT (witness_id, votes, voters_num) VALUES (s.witness_id, s.votes, s.voters_num)
  WHEN NOT MATCHED BY SOURCE THEN DELETE;

  -- Cache 3
  PERFORM hafbe_app.refresh_witness_rank_cache();

  -- Cache 4
  PERFORM hafbe_app.refresh_witness_votes_change_cache(_first_block_num);

END
$$;


/*
 * refresh_witness_votes_cache_delta: Caches 1-3 updated from a set of accounts
 * whose own vests may have changed.
 *
 * PRECONDITION: since the caches were last brought up to date, nothing has changed
 * current_witness_votes, current_account_proxies, current_proposal_votes,
 * current_witnesses or today's witness_votes_history slice; only balances
 * (current_account_balances, account_withdraws) may have moved, and only those of
 * accounts in _impacted. The tracked-account set, every vote and the proxy graph are
 * then the same as at the last refresh, so:
 *   - Cache 1 changes only for tracked accounts in _impacted and their proxy
 *     ancestors (up to 4 levels, whose proxied_vests include them). No key is
 *     added or removed.
 *   - Cache 2 changes by the per-witness sum of the voters' vests deltas; voters_num
 *     and the key set stay as they are.
 *   - Cache 3: see below.
 * process_witness_votes_cache(_block) guarantees the precondition; any other caller
 * must use the full recompute.
 */
CREATE OR REPLACE FUNCTION hafbe_app.refresh_witness_votes_cache_delta(_impacted INT[])
RETURNS VOID
LANGUAGE plpgsql VOLATILE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
AS $$
DECLARE
  _changed           INT[];
  _voters            INT[];
  _deltas            BIGINT[];
  _witnesses_changed INT;
  _min_old_votes     BIGINT;
BEGIN
  -- Cache 1: the impacted tracked accounts and their tracked proxy ancestors.
  -- An impacted account that is not tracked sets no proxy (every proxy setter is
  -- tracked), so it has no ancestors either.
  SELECT array_agg(DISTINCT a.account_id)
  INTO _changed
  FROM unnest(_impacted) AS i (account_id)
  LEFT JOIN hafbe_app.current_account_proxies p1 ON p1.account_id = i.account_id
  LEFT JOIN hafbe_app.current_account_proxies p2 ON p2.account_id = p1.proxy_id
  LEFT JOIN hafbe_app.current_account_proxies p3 ON p3.account_id = p2.proxy_id
  LEFT JOIN hafbe_app.current_account_proxies p4 ON p4.account_id = p3.proxy_id
  CROSS JOIN LATERAL (
    VALUES (i.account_id), (p1.proxy_id), (p2.proxy_id), (p3.proxy_id), (p4.proxy_id)
  ) AS a (account_id)
  WHERE a.account_id IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM hafbe_app.account_vest_stats_cache avs WHERE avs.account_id = a.account_id
    );

  IF _changed IS NULL THEN
    RETURN;
  END IF;

  -- The FROM side reads the rows as they were before this statement, so old_vests
  -- is the value being replaced.
  WITH fresh AS (
    SELECT
      s.account_id,
      s.vests,
      s.account_vests,
      s.proxied_vests,
      t.vests AS old_vests
    FROM hafbe_backend.account_vest_stats_of(_changed) s
    JOIN hafbe_app.account_vest_stats_cache t ON t.account_id = s.account_id
    WHERE (t.vests, t.account_vests, t.proxied_vests)
          IS DISTINCT FROM (s.vests, s.account_vests, s.proxied_vests)
  ),
  updated AS (
    UPDATE hafbe_app.account_vest_stats_cache t
    SET vests = f.vests, account_vests = f.account_vests, proxied_vests = f.proxied_vests
    FROM fresh f
    WHERE t.account_id = f.account_id
    RETURNING t.account_id, f.vests - f.old_vests AS delta
  )
  SELECT array_agg(u.account_id), array_agg(u.delta)
  INTO _voters, _deltas
  FROM updated u
  WHERE u.delta <> 0;

  IF _voters IS NULL THEN
    RETURN;
  END IF;

  -- Cache 2: votes is SUM(vests) over the witness's voters, so it moves by the sum
  -- of their deltas.
  WITH deltas AS (
    SELECT
      cwv.witness_id,
      SUM(v.delta)::BIGINT AS delta
    FROM unnest(_voters, _deltas) AS v (voter_id, delta)
    JOIN hafbe_app.current_witness_votes cwv ON cwv.voter_id = v.voter_id
    GROUP BY cwv.witness_id
  ),
  updated AS (
    UPDATE hafbe_app.witness_votes_cache t
    SET votes = t.votes + d.delta
    FROM deltas d
    WHERE t.witness_id = d.witness_id
      AND d.delta <> 0
    RETURNING t.votes - d.delta AS old_votes
  )
  SELECT count(*), min(u.old_votes)
  INTO _witnesses_changed, _min_old_votes
  FROM updated u;

  IF _witnesses_changed = 0 THEN
    RETURN;
  END IF;

  /*
   * Cache 3. Every witness_votes_cache row has voters_num >= 1, so while its votes
   * are >= 0 it sorts ahead of every witness without a row (0 votes, 0 voters):
   * the current witnesses that have voters hold ranks 1..N, and the rest hold
   * N+1.. ordered by witness_id alone. N and that remainder do not change here (the
   * precondition fixes both sets), so only the first N ranks need recomputing. A
   * row with negative votes, now or before this update, sorts among or after the
   * remainder and shifts it: then rank everything.
   */
  IF _min_old_votes < 0
     OR EXISTS (SELECT 1 FROM hafbe_app.witness_votes_cache wv WHERE wv.votes < 0) THEN
    PERFORM hafbe_app.refresh_witness_rank_cache();
    RETURN;
  END IF;

  UPDATE hafbe_app.witness_rank_cache t
  SET rank = s.rank
  FROM (
    SELECT
      wv.witness_id,
      (ROW_NUMBER() OVER (
        ORDER BY
          wv.votes DESC,
          wv.voters_num DESC,
          wv.witness_id DESC
      ))::INT AS rank
    FROM hafbe_app.witness_votes_cache wv
    JOIN hafbe_app.current_witnesses cw ON cw.witness_id = wv.witness_id
  ) s
  WHERE t.witness_id = s.witness_id
    AND t.rank IS DISTINCT FROM s.rank;
END
$$;


/*
 * witness_votes_cache_full_op_types: the operation types after which
 * process_witness_votes_cache(_block) recomputes the caches in full.
 *
 * Each can change current_witness_votes, current_account_proxies,
 * current_proposal_votes or today's witness_votes_history, i.e. the tracked-account
 * set, the votes or the proxy graph the incremental refresh holds fixed.
 * remove_proposal is here because it deletes current_proposal_votes rows: a voter may
 * leave the tracked set.
 */
CREATE OR REPLACE FUNCTION hafbe_app.witness_votes_cache_full_op_types()
RETURNS INT[]
LANGUAGE sql STABLE
AS $$
  SELECT array_agg(ot.id)
  FROM hafd.operation_types ot
  WHERE ot.name IN (
    'hive::protocol::account_witness_vote_operation',
    'hive::protocol::account_witness_proxy_operation',
    'hive::protocol::proxy_cleared_operation',
    'hive::protocol::declined_voting_rights_operation',
    'hive::protocol::expired_account_notification_operation',
    'hive::protocol::update_proposal_votes_operation',
    'hive::protocol::remove_proposal_operation'
  )
$$;


/*
 * process_witness_votes_cache(): all four caches recomputed in full, with today's
 * window. Leaves witness_votes_cache_state alone: the caches it writes are what any
 * later block's refresh would start from anyway.
 */
CREATE OR REPLACE FUNCTION hafbe_app.process_witness_votes_cache()
RETURNS VOID
LANGUAGE plpgsql VOLATILE
AS $$
BEGIN
  PERFORM hafbe_app.refresh_witness_votes_cache_full(hafbe_app.witness_votes_cache_window_start());
END
$$;


/*
 * process_witness_votes_cache(_block): refresh the caches for LIVE block _block,
 * after every processor has applied it.
 *
 * Takes the full recompute when the block
 *   - is not the direct successor of the block the caches were last refreshed for
 *     (witness_votes_cache_state). The caches are not registered with HAF, so a fork
 *     reverts the tables they are computed from but not the caches; the next block
 *     HAF hands over is then at or below the last refreshed one. The same test
 *     covers the first LIVE block (no state yet) and blocks after a restart or a
 *     MASSIVE catch-up, whose blocks refreshed no cache;
 *   - moves the daily-change window (midnight). Cache 1's account set and Cache 4
 *     must share one window (issue #142);
 *   - carries an operation that can change votes, proxies, the proposal voters or
 *     today's vote history (witness_votes_cache_full_op_types());
 *   - added a current_witnesses row: a new witness takes a rank and shifts the
 *     zero-voter remainder of Cache 3. process_witness_stats() adds rows only for
 *     the accounts its operations name, so it is one of the block's impacted
 *     accounts with no witness_rank_cache row.
 * Otherwise only balances moved, and only those of the accounts the block's
 * operations impact (hive.get_impacted_accounts), so it updates the caches from
 * those accounts (refresh_witness_votes_cache_delta). Cache 4 is recomputed either
 * way.
 *
 * The state row is written in the block's transaction, so it rolls back with it.
 */
CREATE OR REPLACE FUNCTION hafbe_app.process_witness_votes_cache(_block INT)
RETURNS VOID
LANGUAGE plpgsql VOLATILE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
AS $$
DECLARE
  _first_block_num INT := hafbe_app.witness_votes_cache_window_start();
  _last_block      INT;
  _last_first      INT;
  _full_ops        INT[] := hafbe_app.witness_votes_cache_full_op_types();
  _impacted        INT[];
  _full            BOOLEAN;
BEGIN
  SELECT s.block_num, s.first_block_num
  INTO _last_block, _last_first
  FROM hafbe_app.witness_votes_cache_state s;

  _full := _last_block IS DISTINCT FROM _block - 1
    OR _last_first IS DISTINCT FROM _first_block_num
    OR EXISTS (
      SELECT 1
      FROM hafbe_app.operations_view ov
      WHERE ov.op_type_id = ANY(_full_ops)
        AND ov.block_num = _block
        AND ov.id >= hafd.operation_id(_block, 0)
        AND ov.id < hafd.operation_id(_block + 1, 0)
    );

  IF NOT _full THEN
    -- One name lookup per account: the planner, which cannot estimate the
    -- function scan, otherwise joins by hashing every account.
    WITH impacted AS (
      SELECT DISTINCT ia.name
      FROM hafbe_app.operations_view ov
      CROSS JOIN hive.get_impacted_accounts(ov.body::hafd.operation) AS ia (name)
      WHERE ov.block_num = _block
        AND ov.id >= hafd.operation_id(_block, 0)
        AND ov.id < hafd.operation_id(_block + 1, 0)
    )
    SELECT array_agg(r.account_id)
    INTO _impacted
    FROM (
      SELECT (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = i.name) AS account_id
      FROM impacted i
    ) r
    WHERE r.account_id IS NOT NULL;

    _full := EXISTS (
      SELECT 1
      FROM unnest(_impacted) AS i (account_id)
      JOIN hafbe_app.current_witnesses cw ON cw.witness_id = i.account_id
      WHERE NOT EXISTS (
        SELECT 1 FROM hafbe_app.witness_rank_cache r WHERE r.witness_id = i.account_id
      )
    );
  END IF;

  IF _full THEN
    PERFORM hafbe_app.refresh_witness_votes_cache_full(_first_block_num);
  ELSE
    PERFORM hafbe_app.refresh_witness_votes_cache_delta(_impacted);
    PERFORM hafbe_app.refresh_witness_votes_change_cache(_first_block_num);
  END IF;

  INSERT INTO hafbe_app.witness_votes_cache_state (singleton, block_num, first_block_num)
  VALUES (TRUE, _block, _first_block_num)
  ON CONFLICT ON CONSTRAINT pk_witness_votes_cache_state DO UPDATE SET
    block_num       = EXCLUDED.block_num,
    first_block_num = EXCLUDED.first_block_num;
END
$$;

RESET ROLE;
