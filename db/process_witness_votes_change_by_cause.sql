SET ROLE hafbe_owner;

/*
 * ===================================================================================
 * Witness vote change by cause
 * ===================================================================================
 * PURPOSE: Break each witness's vote change over a window (today, 7 days) down by
 * what moved it, for the votes_change_breakdown field of /witnesses.
 *
 * A witness's votes are the sum of its voters' governance weight (own VESTS minus
 * delayed VESTS, plus the VESTS proxied to the voter up to 4 levels deep: the
 * arithmetic of hafbe_backend.account_vest_stats()). Each cause changes one
 * account's weight, or moves a weight onto or off a witness:
 *
 *   cause            source                                          sign
 *   votes_cast       witness_votes_history, approve, by a vote op     +
 *   votes_removed    witness_votes_history, unapprove, by a vote op   -
 *   power_down       account_balance_history, fill_vesting_withdraw   -
 *   power_up         delayed_voting operations                        +
 *   producer_reward  account_balance_history, producer_reward         +
 *   claimed_reward   account_balance_history, claim_reward_balance    +
 *   proxy            account_proxies_history (set, changed, cleared)
 *                    and the vote removals setting a proxy cascades   +/-
 *   expired          expired_account_notification's vote and proxy
 *                    removals                                         -
 *   declined         declined_voting_rights' vote and proxy removals  -
 *
 * Plain power-ups (their VESTS are delayed, so the weight does not move until
 * delayed_voting) and delegations (not governance weight) are not causes.
 *
 * ORDERING RULE. A vote is valued at the voter's weight when it was cast: the
 * current weight minus the voter's later changes in the window. A weight change
 * counts for a witness only while the voter backed it. A voter who votes and then
 * powers down in one window is therefore counted once: the vote at the weight it
 * had, the power-down as its own cause.
 *
 * With every weight change of the window in the event set this telescopes: each
 * witness's total is its votes now minus its votes at the window start.
 *
 * KNOWN APPROXIMATIONS (proxy operations are rare):
 *   - Proxy chains above an account are the current ones. Only the account's own
 *     proxy is taken as it was at the event (account_proxies_history).
 *   - The weight a proxy change moves is the account's current weight minus its
 *     own later changes; changes of accounts proxying to it are not subtracted.
 *   - A power-down is valued at its full VESTS. When it also cancels delayed
 *     VESTS (a power-up still in its 30-day delay) the weight moves by less.
 *
 * Not registered with HAF, like the witness vote caches: a fork reverts the
 * tables this is computed from, and the next block at or below as_of_block
 * triggers a refresh (process_witness_votes_change_by_cause).
 */

/*
 * witness_votes_change_week_start: lower bound of the 7-day window ending at _block.
 *
 * The last block at or before _block's timestamp minus 7 days, the same shape of
 * bound witness_votes_cache_window_start() gives the today window. 0 (the whole
 * chain) when the chain is younger than 7 days.
 */
CREATE OR REPLACE FUNCTION hafbe_app.witness_votes_change_week_start(_block INT)
RETURNS INT
LANGUAGE sql STABLE
AS $$
  SELECT COALESCE((
    SELECT b.num
    FROM hive.blocks_view b
    WHERE b.created_at <= (
      SELECT h.created_at FROM hive.blocks_view h WHERE h.num = _block
    ) - INTERVAL '7 days'
    ORDER BY b.created_at DESC
    LIMIT 1
  ), 0)
$$;


/*
 * witness_votes_change_by_cause_of: each witness's vote change since _first_block
 * (inclusive, to the last processed block), by cause, in one set-based pass.
 *
 * Returns one row per witness and cause that some voter's event moved, and one
 * 'total' row per such witness: vests is the sum of the cause rows' vests, voters
 * the number of distinct voters (the accounts that vote for the witness directly)
 * whose events moved it. No rows for a NULL window.
 *
 * Reads the balance tracker's tables unqualified: the caller's search_path must
 * name its schema, as for every vest query (see account_vest_stats()).
 */
CREATE OR REPLACE FUNCTION hafbe_app.witness_votes_change_by_cause_of(_first_block INT)
RETURNS TABLE (
    witness_id INT,
    cause      TEXT,
    vests      BIGINT,
    voters     INT
)
LANGUAGE plpgsql STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
AS $$
DECLARE
  _first_op           BIGINT := hafd.operation_id(_first_block, 0);
  _nai_vests          INT    := btracker_backend.nai_vests();
  _op_vote            INT    := hafbe_backend.op_account_witness_vote();
  _op_proxy           INT    := hafbe_backend.op_account_witness_proxy();
  _op_expired         INT    := hafbe_backend.op_expired_account_notification();
  _op_declined        INT    := hafbe_backend.op_declined_voting_rights();
  _op_fill_withdraw   INT    := btracker_backend.op_fill_vesting_withdraw();
  _op_producer_reward INT    := hafbe_backend.op_producer_reward();
  _op_claim_reward    INT    := btracker_backend.op_claim_reward_balance();
  _op_delayed_voting  INT    := btracker_backend.op_delayed_voting();
BEGIN
  IF _first_block IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH
  -- Every vote change of the window. An approval is always a vote; a removal is
  -- classified by the operation that made it (process_vote_op, process_proxy_ops'
  -- cascade or process_expired_accounts).
  vote_rows AS MATERIALIZED (
    SELECT
      h.voter_id,
      h.witness_id,
      h.approve,
      h.source_op,
      CASE
        WHEN h.approve THEN 'votes_cast'
        ELSE COALESCE((
          SELECT
            CASE o.op_type_id
              WHEN _op_proxy    THEN 'proxy'
              WHEN _op_expired  THEN 'expired'
              WHEN _op_declined THEN 'declined'
            END
          FROM hafbe_app.operations_view o
          WHERE o.id = h.source_op
        ), 'votes_removed')
      END AS cause
    FROM hafbe_app.witness_votes_history h
    WHERE h.source_op >= _first_op
  ),
  -- Every proxy change of the window, with the proxy it replaced: the previous row
  -- of the account, or for its first row in the window the last row before it.
  link_rows AS MATERIALIZED (
    SELECT
      p.account_id,
      p.source_op,
      CASE WHEN p.proxy THEN p.proxy_id END AS new_proxy,
      LAG(CASE WHEN p.proxy THEN p.proxy_id END) OVER w AS previous_proxy,
      ROW_NUMBER() OVER w AS rn,
      COALESCE((
        SELECT
          CASE o.op_type_id
            WHEN _op_expired  THEN 'expired'
            WHEN _op_declined THEN 'declined'
          END
        FROM hafbe_app.operations_view o
        WHERE o.id = p.source_op
      ), 'proxy') AS cause
    FROM hafbe_app.account_proxies_history p
    WHERE p.source_op >= _first_op
    WINDOW w AS (PARTITION BY p.account_id ORDER BY p.source_op)
  ),
  links AS MATERIALIZED (
    SELECT
      l.account_id,
      l.source_op,
      l.cause,
      l.new_proxy,
      CASE
        WHEN l.rn > 1 THEN l.previous_proxy
        ELSE (
          SELECT CASE WHEN q.proxy THEN q.proxy_id END
          FROM hafbe_app.account_proxies_history q
          WHERE q.account_id = l.account_id
            AND q.source_op < _first_op
          ORDER BY q.source_op DESC
          LIMIT 1
        )
      END AS old_proxy
    FROM link_rows l
  ),
  link_accounts AS MATERIALIZED (
    SELECT DISTINCT l.account_id FROM links l
  ),
  -- The accounts whose weight can reach a witness: voters, proxy setters, and
  -- anyone with a vote or proxy change in the window.
  feeders AS MATERIALIZED (
    SELECT cwv.voter_id AS account_id FROM hafbe_app.current_witness_votes cwv
    UNION
    SELECT cap.account_id FROM hafbe_app.current_account_proxies cap
    UNION
    SELECT v.voter_id FROM vote_rows v
    UNION
    SELECT la.account_id FROM link_accounts la
  ),
  -- The feeders' VESTS balance changes of the window, each as the difference from
  -- the account's previous balance row. One index probe per feeder: the window
  -- function keeps the subquery from being flattened into a join, which the planner
  -- ran as a merge join over the whole (account, nai, block) index.
  balance_rows AS MATERIALIZED (
    SELECT
      f.account_id AS account,
      b.source_op,
      b.op_type_id,
      b.balance,
      b.previous_balance
    FROM feeders f
    CROSS JOIN LATERAL (
      SELECT
        h.source_op,
        h.op_type_id,
        h.balance::BIGINT AS balance,
        COALESCE(
          LAG(h.balance) OVER (ORDER BY h.balance_seq_no),
          (
            SELECT p.balance
            FROM account_balance_history p
            WHERE p.account = f.account_id
              AND p.nai = _nai_vests
              AND p.balance_seq_no < h.balance_seq_no
            ORDER BY p.balance_seq_no DESC
            LIMIT 1
          ),
          0
        )::BIGINT AS previous_balance
      FROM account_balance_history h
      WHERE h.account = f.account_id
        AND h.nai = _nai_vests
        AND hafd.operation_id_to_block_num(h.source_op) >= _first_block
    ) b
  ),
  -- Changes of an account's own weight. A routed fill_vesting_withdraw also credits
  -- VESTS to its recipient, as delayed VESTS: only the withdrawer's side counts.
  own_events AS MATERIALIZED (
    SELECT
      b.account AS account_id,
      b.source_op,
      b.balance - b.previous_balance AS delta,
      CASE b.op_type_id
        WHEN _op_fill_withdraw   THEN 'power_down'
        WHEN _op_producer_reward THEN 'producer_reward'
        ELSE 'claimed_reward'
      END AS cause
    FROM balance_rows b
    WHERE b.op_type_id IN (_op_fill_withdraw, _op_producer_reward, _op_claim_reward)
      AND b.balance <> b.previous_balance
      AND (b.op_type_id <> _op_fill_withdraw OR b.balance < b.previous_balance)
    UNION ALL
    SELECT
      d.account_id,
      d.source_op,
      d.delta,
      'power_up'
    FROM (
      SELECT
        (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = o.body_value ->> 'voter') AS account_id,
        o.id AS source_op,
        (o.body_value ->> 'votes')::BIGINT AS delta
      FROM hafbe_app.operations_view o
      WHERE o.op_type_id = _op_delayed_voting
        AND o.block_num >= _first_block
        AND o.id >= _first_op
    ) d
    WHERE d.delta <> 0
      AND EXISTS (SELECT 1 FROM feeders f WHERE f.account_id = d.account_id)
  ),
  -- The voter at the end of the current proxy chain that starts at an account's
  -- proxy: the first account along it without a proxy, within the 4 levels hived
  -- propagates proxied weight. NULL when the chain is longer.
  chain_tops AS MATERIALIZED (
    SELECT
      s.start_id,
      CASE
        WHEN c1.account_id IS NULL THEN s.start_id
        WHEN c2.account_id IS NULL THEN c1.proxy_id
        WHEN c3.account_id IS NULL THEN c2.proxy_id
        WHEN c4.account_id IS NULL THEN c3.proxy_id
      END AS voter_id
    FROM (
      SELECT cap.proxy_id AS start_id FROM hafbe_app.current_account_proxies cap
      UNION
      SELECT l.old_proxy FROM links l WHERE l.old_proxy IS NOT NULL
      UNION
      SELECT l.new_proxy FROM links l WHERE l.new_proxy IS NOT NULL
    ) s
    LEFT JOIN hafbe_app.current_account_proxies c1 ON c1.account_id = s.start_id
    LEFT JOIN hafbe_app.current_account_proxies c2 ON c2.account_id = c1.proxy_id
    LEFT JOIN hafbe_app.current_account_proxies c3 ON c3.account_id = c2.proxy_id
    LEFT JOIN hafbe_app.current_account_proxies c4 ON c4.account_id = c3.proxy_id
  ),
  -- Each own event with the proxy its account had at the time: the current one,
  -- or for an account whose proxy changed in the window the one in force then.
  routed_own AS MATERIALIZED (
    SELECT
      e.account_id,
      e.source_op,
      e.delta,
      e.cause,
      CASE
        WHEN la.account_id IS NULL THEN cap.proxy_id
        ELSE (
          SELECT CASE WHEN l.source_op < e.source_op THEN l.new_proxy ELSE l.old_proxy END
          FROM links l
          WHERE l.account_id = e.account_id
          ORDER BY
            (l.source_op < e.source_op) DESC,
            CASE WHEN l.source_op < e.source_op THEN -l.source_op ELSE l.source_op END
          LIMIT 1
        )
      END AS proxy_at
    FROM own_events e
    LEFT JOIN link_accounts la ON la.account_id = e.account_id
    LEFT JOIN hafbe_app.current_account_proxies cap ON cap.account_id = e.account_id
  ),
  -- The weight a proxy change moves: the account's weight now minus its own later
  -- changes.
  link_values AS MATERIALIZED (
    SELECT
      l.account_id,
      l.source_op,
      l.cause,
      l.old_proxy,
      l.new_proxy,
      COALESCE(MAX(w.vests), 0) - COALESCE(SUM(e.delta), 0) AS weight
    FROM links l
    LEFT JOIN hafbe_backend.account_vest_stats_of(ARRAY(SELECT la.account_id FROM link_accounts la)) w
      ON w.account_id = l.account_id
    LEFT JOIN own_events e ON e.account_id = l.account_id AND e.source_op > l.source_op
    WHERE l.old_proxy IS DISTINCT FROM l.new_proxy
    GROUP BY l.account_id, l.source_op, l.cause, l.old_proxy, l.new_proxy
  ),
  -- Every change of a voter's weight, at the voter it reached. backs = FALSE marks
  -- a change of the voter's own VESTS made while it proxied them to another voter:
  -- it moved that voter's witnesses, not its own, but still changed its weight.
  weight_events AS (
    SELECT
      CASE WHEN r.proxy_at IS NULL THEN r.account_id ELSE ct.voter_id END AS voter_id,
      r.source_op,
      r.delta,
      r.cause,
      TRUE AS backs
    FROM routed_own r
    LEFT JOIN chain_tops ct ON ct.start_id = r.proxy_at
    UNION ALL
    SELECT r.account_id, r.source_op, r.delta, r.cause, FALSE
    FROM routed_own r
    WHERE r.proxy_at IS NOT NULL
    UNION ALL
    SELECT ct.voter_id, lv.source_op, -lv.weight, lv.cause, TRUE
    FROM link_values lv
    JOIN chain_tops ct ON ct.start_id = lv.old_proxy
    UNION ALL
    SELECT ct.voter_id, lv.source_op, lv.weight, lv.cause, TRUE
    FROM link_values lv
    JOIN chain_tops ct ON ct.start_id = lv.new_proxy
  ),
  -- A voter's vote changes split its window into segments: segment k follows its
  -- k-th distinct vote operation. Each weight event falls in the segment of the
  -- vote changes strictly before it.
  marks AS MATERIALIZED (
    SELECT
      v.voter_id,
      v.source_op,
      ROW_NUMBER() OVER (PARTITION BY v.voter_id ORDER BY v.source_op)::INT AS mark
    FROM (SELECT DISTINCT vr.voter_id, vr.source_op FROM vote_rows vr) v
  ),
  segmented AS MATERIALIZED (
    SELECT
      t.voter_id,
      t.delta,
      t.cause,
      t.backs,
      t.is_mark,
      SUM(t.is_mark) OVER (
        PARTITION BY t.voter_id
        ORDER BY t.source_op, t.is_mark
        ROWS UNBOUNDED PRECEDING
      )::INT AS seg
    FROM (
      SELECT we.voter_id, we.source_op, we.delta, we.cause, we.backs, 0 AS is_mark
      FROM weight_events we
      WHERE we.voter_id IS NOT NULL
        AND we.delta <> 0
      UNION ALL
      SELECT m.voter_id, m.source_op, 0, NULL, FALSE, 1
      FROM marks m
    ) t
  ),
  segment_sums AS MATERIALIZED (
    SELECT s.voter_id, s.seg, s.cause, SUM(s.delta)::BIGINT AS delta
    FROM segmented s
    WHERE s.is_mark = 0
      AND s.backs
    GROUP BY s.voter_id, s.seg, s.cause
  ),
  -- Everything that changed a voter's weight, per segment.
  segment_totals AS (
    SELECT s.voter_id, s.seg, SUM(s.delta)::BIGINT AS delta
    FROM segmented s
    WHERE s.is_mark = 0
    GROUP BY s.voter_id, s.seg
  ),
  vote_marks AS MATERIALIZED (
    SELECT vr.voter_id, vr.witness_id, vr.approve, vr.source_op, vr.cause, m.mark
    FROM vote_rows vr
    JOIN marks m ON m.voter_id = vr.voter_id AND m.source_op = vr.source_op
  ),
  mark_counts AS (
    SELECT m.voter_id, MAX(m.mark) AS last_mark
    FROM marks m
    GROUP BY m.voter_id
  ),
  -- The segments in which a voter backed a witness, as [seg_from, seg_to].
  backing AS (
    -- after an approval, until the pair's next vote change
    SELECT x.voter_id, x.witness_id, x.seg_from, x.seg_to
    FROM (
      SELECT
        vm.voter_id,
        vm.witness_id,
        vm.approve,
        vm.mark AS seg_from,
        COALESCE(LEAD(vm.mark) OVER (PARTITION BY vm.voter_id, vm.witness_id ORDER BY vm.source_op) - 1, mc.last_mark) AS seg_to
      FROM vote_marks vm
      JOIN mark_counts mc ON mc.voter_id = vm.voter_id
    ) x
    WHERE x.approve
    UNION ALL
    -- from the window start, when the pair's first change in it is a removal
    SELECT f.voter_id, f.witness_id, 0, f.mark - 1
    FROM (
      SELECT DISTINCT ON (vm.voter_id, vm.witness_id) vm.voter_id, vm.witness_id, vm.approve, vm.mark
      FROM vote_marks vm
      ORDER BY vm.voter_id, vm.witness_id, vm.source_op
    ) f
    WHERE NOT f.approve
    UNION ALL
    -- a current vote the window did not touch, of a voter with other vote changes
    SELECT cwv.voter_id, cwv.witness_id, 0, mc.last_mark
    FROM hafbe_app.current_witness_votes cwv
    JOIN mark_counts mc ON mc.voter_id = cwv.voter_id
    WHERE NOT EXISTS (
      SELECT 1 FROM vote_marks vm WHERE vm.voter_id = cwv.voter_id AND vm.witness_id = cwv.witness_id
    )
    UNION ALL
    -- the votes of a voter without vote changes in the window
    SELECT cwv.voter_id, cwv.witness_id, 0, 0
    FROM hafbe_app.current_witness_votes cwv
    WHERE NOT EXISTS (SELECT 1 FROM mark_counts mc WHERE mc.voter_id = cwv.voter_id)
  ),
  voter_weights AS MATERIALIZED (
    SELECT w.account_id, w.vests
    FROM hafbe_backend.account_vest_stats_of(ARRAY(SELECT DISTINCT vr.voter_id FROM vote_rows vr)) w
  ),
  -- A vote change at the voter's weight then: its weight now minus every change of
  -- it after the vote (segments from the vote's own on).
  vote_values AS (
    SELECT
      vm.witness_id,
      vm.voter_id,
      vm.cause,
      vm.approve,
      COALESCE(MAX(vw.vests), 0) - COALESCE(SUM(st.delta), 0) AS weight
    FROM vote_marks vm
    LEFT JOIN voter_weights vw ON vw.account_id = vm.voter_id
    LEFT JOIN segment_totals st ON st.voter_id = vm.voter_id AND st.seg >= vm.mark
    GROUP BY vm.witness_id, vm.voter_id, vm.cause, vm.approve, vm.source_op
  ),
  contributions AS MATERIALIZED (
    SELECT c.witness_id, c.cause, c.voter_id, SUM(c.delta)::BIGINT AS delta
    FROM (
      SELECT b.witness_id, ss.cause, ss.voter_id, ss.delta
      FROM segment_sums ss
      JOIN backing b
        ON b.voter_id = ss.voter_id
        AND ss.seg BETWEEN b.seg_from AND b.seg_to
      UNION ALL
      SELECT
        vv.witness_id,
        vv.cause,
        vv.voter_id,
        CASE WHEN vv.approve THEN vv.weight ELSE -vv.weight END
      FROM vote_values vv
    ) c
    GROUP BY c.witness_id, c.cause, c.voter_id
  )
  SELECT c.witness_id, c.cause, SUM(c.delta)::BIGINT, (COUNT(*) FILTER (WHERE c.delta <> 0))::INT
  FROM contributions c
  GROUP BY c.witness_id, c.cause
  UNION ALL
  SELECT c.witness_id, 'total', SUM(c.delta)::BIGINT, (COUNT(DISTINCT c.voter_id) FILTER (WHERE c.delta <> 0))::INT
  FROM contributions c
  GROUP BY c.witness_id;
END
$$;


/*
 * witness_votes_change_by_cause_indexes_ready: whether the balance tracker's
 * account_balance_history indexes the pass probes per account are built and valid.
 *
 * They are HAF-registered indexes of the balance tracker's context, absent during
 * its massive sync and built at the switch to LIVE; without them each probe is a
 * scan of the whole table. Resolved through the search_path, like the tables.
 */
CREATE OR REPLACE FUNCTION hafbe_app.witness_votes_change_by_cause_indexes_ready()
RETURNS BOOLEAN
LANGUAGE sql STABLE
AS $$
  SELECT COUNT(*) = 2
  FROM pg_index i
  WHERE i.indexrelid IN (
      to_regclass('idx_account_balance_history_account_block_num_idx'),
      to_regclass('idx_account_balance_history_account_seq_num_idx')
    )
    AND i.indisvalid
$$;


/*
 * refresh_witness_votes_change_by_cause: both windows recomputed for _block, the
 * last processed block, and written where they changed.
 *
 * The today window is the daily-change window of votes_daily_change
 * (witness_votes_cache_window_start()), the 7-day one ends at _block.
 *
 * Raises when witness_votes_change_by_cause_indexes_ready() is false.
 */
CREATE OR REPLACE FUNCTION hafbe_app.refresh_witness_votes_change_by_cause(_block INT)
RETURNS VOID
LANGUAGE plpgsql VOLATILE
AS $$
DECLARE
  _today_first_block INT := hafbe_app.witness_votes_cache_window_start();
  _week_first_block  INT := hafbe_app.witness_votes_change_week_start(_block);
BEGIN
  IF NOT hafbe_app.witness_votes_change_by_cause_indexes_ready() THEN
    RAISE EXCEPTION 'the balance tracker''s account_balance_history indexes are missing or invalid: restore its registered indexes (hive.app_restore_indexes) first';
  END IF;

  MERGE INTO hafbe_app.witness_votes_change_by_cause t
  USING (
    SELECT c.witness_id, 'today' AS time_window, c.cause, c.vests, c.voters
    FROM hafbe_app.witness_votes_change_by_cause_of(_today_first_block) c
    UNION ALL
    SELECT c.witness_id, '7d', c.cause, c.vests, c.voters
    FROM hafbe_app.witness_votes_change_by_cause_of(_week_first_block) c
  ) s ON t.witness_id = s.witness_id AND t.time_window = s.time_window AND t.cause = s.cause
  WHEN MATCHED AND (t.vests, t.voters) IS DISTINCT FROM (s.vests, s.voters) THEN
    UPDATE SET vests = s.vests, voters = s.voters
  WHEN NOT MATCHED THEN
    INSERT (witness_id, time_window, cause, vests, voters)
    VALUES (s.witness_id, s.time_window, s.cause, s.vests, s.voters)
  WHEN NOT MATCHED BY SOURCE THEN DELETE;

  INSERT INTO hafbe_app.witness_votes_change_by_cause_state (singleton, as_of_block, today_first_block, week_first_block)
  VALUES (TRUE, _block, _today_first_block, _week_first_block)
  ON CONFLICT ON CONSTRAINT pk_witness_votes_change_by_cause_state DO UPDATE SET
    as_of_block       = EXCLUDED.as_of_block,
    today_first_block = EXCLUDED.today_first_block,
    week_first_block  = EXCLUDED.week_first_block;
END
$$;


/*
 * process_witness_votes_change_by_cause(_block): what single_processing() runs for
 * LIVE block _block, after the witness vote caches.
 *
 * Refreshes every 100 blocks (~5 minutes), and right away when nothing was
 * refreshed yet or the last refresh is at or above _block (a fork reverted it).
 * Skips, with a NOTICE, while the balance tracker's indexes are not built yet (the
 * first LIVE blocks), rather than scan its history once per account.
 */
CREATE OR REPLACE FUNCTION hafbe_app.process_witness_votes_change_by_cause(_block INT)
RETURNS VOID
LANGUAGE plpgsql VOLATILE
AS $$
DECLARE
  _as_of_block INT := (SELECT s.as_of_block FROM hafbe_app.witness_votes_change_by_cause_state s);
BEGIN
  IF _block % 100 = 0 OR _as_of_block IS NULL OR _as_of_block >= _block THEN
    IF NOT hafbe_app.witness_votes_change_by_cause_indexes_ready() THEN
      RAISE NOTICE 'witness_votes_change_by_cause: not refreshed at block %, the balance tracker''s indexes are not built yet', _block;
      RETURN;
    END IF;
    PERFORM hafbe_app.refresh_witness_votes_change_by_cause(_block);
  END IF;
END
$$;


/*
 * process_witness_votes_change_by_cause(): refresh for the last block hafbe
 * processed, outside block processing (CI's sync).
 */
CREATE OR REPLACE FUNCTION hafbe_app.process_witness_votes_change_by_cause()
RETURNS VOID
LANGUAGE plpgsql VOLATILE
AS $$
BEGIN
  PERFORM hafbe_app.refresh_witness_votes_change_by_cause(
    (SELECT c.current_block_num FROM hafd.contexts c WHERE c.name = 'hafbe_app')
  );
END
$$;

RESET ROLE;
