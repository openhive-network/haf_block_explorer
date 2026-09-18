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
LANGUAGE 'plpgsql' VOLATILE
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
 * process_witness_votes_cache
 * ===================================================================================
 * PURPOSE: Refreshes cached witness vote statistics for fast API queries.
 *
 * This function refreshes several cache tables used by the witness-related
 * API endpoints. It runs on every LIVE block (not during MASSIVE).
 *
 * CACHE TABLES UPDATED:
 *   - account_vest_stats_cache: Vesting power per account (own + proxied),
 *       covering current voters/proxies/proposal voters plus anyone with a
 *       witness vote event in today's window (issue #142)
 *   - witness_votes_cache: Total votes and voter count per witness
 *   - witness_rank_cache: Witness rankings by vote weight
 *   - witness_votes_change_cache: Daily vote changes (for "24h change" stats)
 *
 * NOTE: Each cache is still fully RECOMPUTED every block, but it is applied with
 *   MERGE so that only rows whose values actually changed are written (plus
 *   inserts for new keys and deletes for keys that left the source set). The
 *   result is identical to the old DELETE + INSERT, which rewrote all ~25,500
 *   rows every block when typically ~150 change: ~4.9 MB of WAL per block
 *   (~140 GB/day) and ~25k dead tuples per block. Whenever anything held an old
 *   snapshot (a long API query, pg_dump, CREATE INDEX CONCURRENTLY) those dead
 *   tuples could not be vacuumed, the tables bloated without bound, and the
 *   per-block refresh slowed linearly until block processing fell behind.
 *   MERGE ... WHEN NOT MATCHED BY SOURCE requires PostgreSQL 17+, HAF's floor.
 *   Statement ORDER still matters: caches 2-4 read cache 1 (and 3 reads 2) as
 *   refreshed earlier in this same transaction.
 */
CREATE OR REPLACE FUNCTION hafbe_app.process_witness_votes_cache()
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
AS $$
DECLARE
  -- Lower bound of the "daily change" window. Strictly this is the LAST block at or
  -- before today's midnight -- i.e. usually the final block of yesterday -- and the
  -- window below is inclusive of it, so one pre-midnight block counts as today. That
  -- off-by-one is pre-existing behaviour, preserved deliberately; correcting it moves
  -- published numbers and belongs in its own change.
  -- CURRENT_DATE, not 'today'::DATE: the latter is a literal cast, folded to a
  -- constant at PLAN time, so once plpgsql caches a generic plan the window
  -- freezes at whatever day that plan was built and never rolls over. Both
  -- consumers below (Cache 1's argument and Cache 4's predicate) read this one
  -- variable, so they stay consistent within the block transaction either way.
  _first_block_num INT := (
    SELECT num
    FROM hive.blocks_view
    WHERE created_at <= CURRENT_DATE
    ORDER BY num DESC
    LIMIT 1
  );
BEGIN

  /*
   * ===================================================================================
   * Cache 1: Account Vest Stats
   * ===================================================================================
   * Caches vesting power statistics for each account:
   *   - vests: Total effective vesting power (own + proxied to this account)
   *   - account_vests: Account's own vesting power
   *   - proxied_vests: Vesting power proxied to this account by others
   */
  /*
   * _first_block_num is passed so the account set also covers voters with a vote
   * event inside today's window, including those who have just stopped being
   * current voters. That is what makes Cache 4's INNER JOIN below lossless
   * (issue #142); the two must share one window or they can drift apart.
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


  /*
   * ===================================================================================
   * Cache 3: Witness Rank
   * ===================================================================================
   * Caches witness rankings based on vote weight.
   * Ranking criteria (in order):
   *   1. Total votes (DESC)
   *   2. Number of voters (DESC)
   *   3. Witness ID (DESC) - tiebreaker
   */
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


  /*
   * ===================================================================================
   * Cache 4: Witness Votes Daily Change
   * ===================================================================================
   * Caches the change in votes and voters for each witness since start of today.
   * Used for "24h change" statistics in the API.
   *
   * Calculation:
   *   - Positive vests for approve=TRUE votes
   *   - Negative vests for approve=FALSE votes
   *   - Sum gives net change in vote weight
   *
   * The INNER JOIN is safe ONLY because Cache 1 was built with this same
   * _first_block_num — see the fourth tracked_accounts branch in
   * hafbe_backend.account_vest_stats() (issue #142). Narrowing it re-opens the bug.
   *
   * Filtering source_op rather than the decoded block number keeps the predicate
   * sargable: hafd.operation_id(b, 0) is the minimum operation id in block b, so
   * this is exactly equivalent to source_op_block >= _first_block_num -- EXCEPT for
   * NULL, which is why the guard is explicit. hafd.operation_id is non-STRICT and
   * reads a NULL block number as 0, so without it a NULL window would aggregate all
   * of history rather than nothing.
   */
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

RESET ROLE;
