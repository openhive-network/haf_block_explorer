SET ROLE hafbe_owner;

/*
 * ===================================================================================
 * Witness vote change by cause
 * ===================================================================================
 * PURPOSE: Break each witness's vote change over a window (today, 7 days) down by
 * what moved it, for the votes_change_breakdown field of /witnesses; and each
 * proposal's, with its place against the return proposal, for /proposals (#209:
 * the same pass, see votes_change_by_cause_of()).
 *
 * A witness's votes are the sum of its voters' governance weight (own VESTS minus
 * delayed VESTS, plus the VESTS proxied to the voter up to 4 levels deep: the
 * arithmetic of hafbe_backend.account_vest_stats()). Each cause changes one
 * account's weight, or moves a weight onto or off a witness:
 *
 *   cause            source                                          sign
 *   votes_cast       witness_votes_history, approve, by a vote op     +
 *   votes_removed    witness_votes_history, unapprove, by a vote op   -
 *   power_down       account_balance_history, fill_vesting_withdraw,  -
 *                    and withdraw_delayed_vests
 *   power_up         delayed_voting operations                        +
 *   producer_reward  account_balance_history, producer_reward         +
 *   claimed_reward   account_balance_history, claim_reward_balance    +
 *   proxy            account_proxies_history (set, changed, cleared)
 *                    and the vote removals setting a proxy cascades   +/-
 *   expired          expired_account_notification's vote removals,
 *                    and the proxy removal in its block               -
 *   declined         declined_voting_rights' vote removals, and the
 *                    proxy removal in its block                       -
 *
 * An account's proxy at any point is the one its last set named, unless a later
 * row cleared that same proxy: the proxy_cleared hived pushes for the replaced
 * proxy after a switch is not a removal.
 *
 * Plain power-ups (their VESTS are delayed, so the weight does not move until
 * delayed_voting) and delegations (not governance weight) are not causes.
 *
 * A power-down payout moves the withdrawer's weight by its VESTS change plus the
 * delayed VESTS it took: hived takes a payout from the delayed VESTS first
 * (delayed_voting::update_votes), and those never mature. The balance tracker
 * records what each fill_vesting_withdraw took in withdraw_delayed_vests. hived
 * emits one fill per VESTS route, then one for the rest: a route back to the
 * withdrawer is a fill with a withdrawal and a deposit row for it, whose change is
 * their sum (0).
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
 *   - An account that had votes and sets a proxy in the window: the later events
 *     of accounts proxying to it go to its new chain top, while its removed votes
 *     are valued at its current weight, which already includes those events. Its
 *     witnesses' proxy cause is off by their sum.
 *   - VESTS changes by other operations are not causes. Since HF24 power-ups and
 *     routed withdrawals reach the weight through delayed_voting, and since HF19
 *     rewards through claim_reward_balance; in older history (CI's 5M-block chain)
 *     they moved it directly and are missing from the totals.
 *
 * Not registered with HAF, like the witness vote caches: a fork reverts the
 * tables this is computed from, and a check at a block below as_of_block
 * triggers a refresh (process_witness_votes_change_by_cause).
 */

/*
 * witness_votes_change_today_start(_block): first block of the today window ending
 * at _block, the first block at or after 00:00 UTC of _block's day. The same window
 * as votes_daily_change's (witness_votes_cache_window_start(_block)).
 */
DROP FUNCTION IF EXISTS hafbe_app.witness_votes_change_today_start();
CREATE OR REPLACE FUNCTION hafbe_app.witness_votes_change_today_start(_block INT)
RETURNS INT
LANGUAGE sql STABLE
AS $$
  SELECT hafbe_app.witness_votes_cache_window_start(_block)
$$;


/*
 * witness_votes_change_week_start: first block of the 7-day window ending at
 * _block, the first block at or after _block's timestamp minus 7 days.
 */
CREATE OR REPLACE FUNCTION hafbe_app.witness_votes_change_week_start(_block INT)
RETURNS INT
LANGUAGE sql STABLE
AS $$
  SELECT b.num
  FROM hive.blocks_view b
  WHERE b.created_at >= (
    SELECT h.created_at FROM hive.blocks_view h WHERE h.num = _block
  ) - INTERVAL '7 days'
  ORDER BY b.created_at
  LIMIT 1
$$;


/*
 * votes_change_by_cause_of: each witness's and each proposal's vote change since
 * _first_block (inclusive, to the last processed block), by cause, in one set-based
 * pass over the voters' events (#209).
 *
 * Returns one row per target (target_kind 'witness' or 'proposal', target_id the
 * witness's account id or the proposal id) and cause that some voter's event moved,
 * and one 'total' row per such target: vests is the sum of the cause rows' vests,
 * voters the number of distinct voters (the accounts that vote for the target
 * directly) whose events moved it. No rows for a NULL window.
 *
 * A proposal's votes are the governance weight of its approvers without a proxy
 * (dhf_processor::calculate_votes, proposal_vote_stats_cache): an approver's weight
 * counts for a proposal while it approves it and has no proxy. Unlike witness votes,
 * which setting a proxy removes (process_proxy_ops' cascade), hived keeps the
 * proposal votes of an account that sets a proxy and ignores them until it clears it:
 * the set and the clear start and stop them counting, as the proxy cause. A proxied
 * account's weight reaches a proposal only through the voter at the end of its chain,
 * as for witnesses.
 *
 * Reads the balance tracker's tables unqualified: the caller's search_path must
 * name its schema, as for every vest query (see account_vest_stats()).
 */
CREATE OR REPLACE FUNCTION hafbe_app.votes_change_by_cause_of(_first_block INT)
RETURNS TABLE (
    target_kind TEXT,
    target_id   INT,
    cause       TEXT,
    vests       BIGINT,
    voters      INT
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
  -- Every witness vote change of the window. An approval is always a vote; a
  -- removal is classified by the operation that made it (process_vote_op,
  -- process_proxy_ops' cascade or process_expired_accounts).
  witness_vote_rows AS MATERIALIZED (
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
  -- The accounts with a proxy row in the window, and their rows from the last one
  -- before the window that set a proxy on (no such row: no proxy at the window
  -- start). set_no numbers each row by the sets so far.
  window_proxy_accounts AS MATERIALIZED (
    SELECT DISTINCT p.account_id
    FROM hafbe_app.account_proxies_history p
    WHERE p.source_op >= _first_op
  ),
  proxy_rows AS MATERIALIZED (
    SELECT
      r.account_id,
      r.proxy_id,
      r.proxy,
      r.source_op,
      COUNT(*) FILTER (WHERE r.proxy) OVER (PARTITION BY r.account_id ORDER BY r.source_op) AS set_no
    FROM window_proxy_accounts a
    CROSS JOIN LATERAL (
      SELECT q.account_id, q.proxy_id, q.proxy, q.source_op
      FROM hafbe_app.account_proxies_history q
      WHERE q.account_id = a.account_id
        AND q.source_op >= COALESCE((
          SELECT s.source_op
          FROM hafbe_app.account_proxies_history s
          WHERE s.account_id = a.account_id
            AND s.proxy
            AND s.source_op < _first_op
          ORDER BY s.source_op DESC
          LIMIT 1
        ), _first_op)
    ) r
  ),
  -- The proxy an account has after each row: the one its last set named, unless a
  -- row since cleared that same proxy. Clearing another one changes nothing: hived
  -- pushes proxy_cleared for the replaced proxy after the account_witness_proxy that
  -- switched to a new one, as process_proxy_ops records it.
  proxy_states AS MATERIALIZED (
    SELECT
      c.account_id,
      c.proxy,
      c.source_op,
      CASE WHEN NOT c.cleared THEN c.set_proxy END AS state
    FROM (
      SELECT
        f.account_id,
        f.proxy,
        f.source_op,
        f.set_proxy,
        BOOL_OR(NOT f.proxy AND f.proxy_id = f.set_proxy) OVER (
          PARTITION BY f.account_id, f.set_no ORDER BY f.source_op
        ) AS cleared
      FROM (
        SELECT
          pr.account_id,
          pr.proxy_id,
          pr.proxy,
          pr.source_op,
          pr.set_no,
          FIRST_VALUE(CASE WHEN pr.proxy THEN pr.proxy_id END) OVER (
            PARTITION BY pr.account_id, pr.set_no ORDER BY pr.source_op
          ) AS set_proxy
        FROM proxy_rows pr
      ) f
    ) c
  ),
  -- Every proxy change of the window, with the proxy it replaced. A removal is
  -- classified by an expiry or decline of the account at or after it in its block:
  -- hived pushes proxy_cleared before expired_account_notification /
  -- declined_voting_rights (process_expired_accounts records its own removals at
  -- the expiry itself).
  links AS MATERIALIZED (
    SELECT
      l.account_id,
      l.source_op,
      l.new_proxy,
      l.old_proxy,
      CASE
        WHEN l.proxy THEN 'proxy'
        ELSE COALESCE((
          SELECT
            CASE o.op_type_id
              WHEN _op_expired  THEN 'expired'
              WHEN _op_declined THEN 'declined'
            END
          FROM hafbe_app.operations_view o
          WHERE o.id >= l.source_op
            AND o.id < hafd.operation_id(hafd.operation_id_to_block_num(l.source_op) + 1, 0)
            AND o.op_type_id IN (_op_expired, _op_declined)
            AND o.body_value ->> 'account' = (SELECT av.name FROM hafbe_app.accounts_view av WHERE av.id = l.account_id)
          ORDER BY o.id
          LIMIT 1
        ), 'proxy')
      END AS cause
    FROM (
      SELECT
        ps.account_id,
        ps.source_op,
        ps.proxy,
        ps.state AS new_proxy,
        LAG(ps.state) OVER (PARTITION BY ps.account_id ORDER BY ps.source_op) AS old_proxy
      FROM proxy_states ps
    ) l
    WHERE l.source_op >= _first_op
      AND l.old_proxy IS DISTINCT FROM l.new_proxy
  ),
  link_accounts AS MATERIALIZED (
    SELECT DISTINCT l.account_id FROM links l
  ),
  -- Every proposal approval change of the window. hived accepts an
  -- update_proposal_votes that names a proposal the voter already approves (or does
  -- not), and process_proposals logs a row for each: only a row that changes the
  -- pair's approval, from the pair's previous row (before the window too), is one.
  -- A removal is classified by its operation (process_proposal_expired_account), a
  -- proposal's removal by remove_proposal as votes_removed.
  proposal_history_rows AS MATERIALIZED (
    SELECT
      h.voter_id,
      h.proposal_id,
      h.approve,
      h.source_op,
      COALESCE(
        LAG(h.approve) OVER (PARTITION BY h.voter_id, h.proposal_id ORDER BY h.source_op),
        (
          SELECT q.approve
          FROM hafbe_app.proposal_votes_history q
          WHERE q.proposal_id = h.proposal_id
            AND q.voter_id = h.voter_id
            AND q.source_op < _first_op
          ORDER BY q.source_op DESC
          LIMIT 1
        ),
        FALSE
      ) AS was_approved
    FROM hafbe_app.proposal_votes_history h
    WHERE h.source_op >= _first_op
  ),
  -- The proposal vote changes that moved a proposal's votes: those of a voter
  -- without a proxy at the time (as routed_own takes it), and each proposal its
  -- voter approved when a proxy set or clear stopped or started them counting. A
  -- switch from one proxy to another changes nothing.
  proposal_vote_rows AS MATERIALIZED (
    SELECT
      p.voter_id,
      p.proposal_id,
      p.approve,
      p.source_op,
      CASE
        WHEN p.approve THEN 'votes_cast'
        ELSE COALESCE((
          SELECT
            CASE o.op_type_id
              WHEN _op_expired  THEN 'expired'
              WHEN _op_declined THEN 'expired'
            END
          FROM hafbe_app.operations_view o
          WHERE o.id = p.source_op
        ), 'votes_removed')
      END AS cause
    FROM proposal_history_rows p
    LEFT JOIN link_accounts la ON la.account_id = p.voter_id
    LEFT JOIN hafbe_app.current_account_proxies cap ON cap.account_id = p.voter_id
    WHERE p.approve <> p.was_approved
      AND CASE
            WHEN la.account_id IS NULL THEN cap.proxy_id
            ELSE (
              SELECT CASE WHEN l.source_op < p.source_op THEN l.new_proxy ELSE l.old_proxy END
              FROM links l
              WHERE l.account_id = p.voter_id
              ORDER BY
                (l.source_op < p.source_op) DESC,
                CASE WHEN l.source_op < p.source_op THEN -l.source_op ELSE l.source_op END
              LIMIT 1
            )
          END IS NULL
    UNION ALL
    SELECT s.account_id, s.proposal_id, s.new_proxy IS NULL, s.source_op, s.cause
    FROM (
      SELECT
        l.account_id,
        l.source_op,
        l.new_proxy,
        l.cause,
        h.proposal_id,
        h.approve,
        ROW_NUMBER() OVER (PARTITION BY l.account_id, l.source_op, h.proposal_id ORDER BY h.source_op DESC) AS n
      FROM links l
      JOIN hafbe_app.proposal_votes_history h
        ON h.voter_id = l.account_id
        AND h.source_op < l.source_op
      WHERE (l.old_proxy IS NULL) <> (l.new_proxy IS NULL)
    ) s
    WHERE s.n = 1
      AND s.approve
  ),
  -- Every vote change of the window, of a witness or a proposal.
  vote_rows AS MATERIALIZED (
    SELECT w.voter_id, 'witness'::TEXT AS target_kind, w.witness_id AS target_id, w.approve, w.source_op, w.cause
    FROM witness_vote_rows w
    UNION ALL
    SELECT p.voter_id, 'proposal', p.proposal_id, p.approve, p.source_op, p.cause
    FROM proposal_vote_rows p
  ),
  -- The accounts whose weight can reach a witness or a proposal: voters, proxy
  -- setters, and anyone with a vote or proxy change in the window.
  feeders AS MATERIALIZED (
    SELECT cwv.voter_id AS account_id FROM hafbe_app.current_witness_votes cwv
    UNION
    SELECT cpv.voter_id FROM hafbe_app.current_proposal_votes cpv
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
  -- Changes of an account's own weight. A payout's: its VESTS change (all its rows
  -- for the account) plus the delayed VESTS it took, when that lowers the weight. A
  -- payout routed to another account credits the recipient delayed VESTS, which
  -- move no weight until delayed_voting: its net change is positive.
  own_events AS MATERIALIZED (
    SELECT
      p.account AS account_id,
      p.source_op,
      p.delta + COALESCE(t.delayed_vests, 0) AS delta,
      'power_down' AS cause
    FROM (
      SELECT b.account, b.source_op, SUM(b.balance - b.previous_balance)::BIGINT AS delta
      FROM balance_rows b
      WHERE b.op_type_id = _op_fill_withdraw
      GROUP BY b.account, b.source_op
    ) p
    LEFT JOIN withdraw_delayed_vests t ON t.account = p.account AND t.source_op = p.source_op
    WHERE p.delta + COALESCE(t.delayed_vests, 0) < 0
    UNION ALL
    SELECT
      b.account,
      b.source_op,
      b.balance - b.previous_balance,
      CASE b.op_type_id
        WHEN _op_producer_reward THEN 'producer_reward'
        ELSE 'claimed_reward'
      END
    FROM balance_rows b
    WHERE b.op_type_id IN (_op_producer_reward, _op_claim_reward)
      AND b.balance <> b.previous_balance
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
    SELECT vr.voter_id, vr.target_kind, vr.target_id, vr.approve, vr.source_op, vr.cause, m.mark
    FROM vote_rows vr
    JOIN marks m ON m.voter_id = vr.voter_id AND m.source_op = vr.source_op
  ),
  mark_counts AS (
    SELECT m.voter_id, MAX(m.mark) AS last_mark
    FROM marks m
    GROUP BY m.voter_id
  ),
  -- The votes in force now: a witness vote, or a proposal vote of a voter without a
  -- proxy (one with a proxy counts for no proposal).
  current_votes AS MATERIALIZED (
    SELECT cwv.voter_id, 'witness'::TEXT AS target_kind, cwv.witness_id AS target_id
    FROM hafbe_app.current_witness_votes cwv
    UNION ALL
    SELECT cpv.voter_id, 'proposal', cpv.proposal_id
    FROM hafbe_app.current_proposal_votes cpv
    WHERE NOT EXISTS (SELECT 1 FROM hafbe_app.current_account_proxies cap WHERE cap.account_id = cpv.voter_id)
  ),
  -- The segments in which a voter backed a target, as [seg_from, seg_to].
  backing AS (
    -- after an approval, until the pair's next vote change
    SELECT x.voter_id, x.target_kind, x.target_id, x.seg_from, x.seg_to
    FROM (
      SELECT
        vm.voter_id,
        vm.target_kind,
        vm.target_id,
        vm.approve,
        vm.mark AS seg_from,
        COALESCE(LEAD(vm.mark) OVER (PARTITION BY vm.voter_id, vm.target_kind, vm.target_id ORDER BY vm.source_op) - 1, mc.last_mark) AS seg_to
      FROM vote_marks vm
      JOIN mark_counts mc ON mc.voter_id = vm.voter_id
    ) x
    WHERE x.approve
    UNION ALL
    -- from the window start, when the pair's first change in it is a removal
    SELECT f.voter_id, f.target_kind, f.target_id, 0, f.mark - 1
    FROM (
      SELECT DISTINCT ON (vm.voter_id, vm.target_kind, vm.target_id) vm.voter_id, vm.target_kind, vm.target_id, vm.approve, vm.mark
      FROM vote_marks vm
      ORDER BY vm.voter_id, vm.target_kind, vm.target_id, vm.source_op
    ) f
    WHERE NOT f.approve
    UNION ALL
    -- a current vote the window did not touch, of a voter with other vote changes
    SELECT cv.voter_id, cv.target_kind, cv.target_id, 0, mc.last_mark
    FROM current_votes cv
    JOIN mark_counts mc ON mc.voter_id = cv.voter_id
    WHERE NOT EXISTS (
      SELECT 1 FROM vote_marks vm
      WHERE vm.voter_id = cv.voter_id AND vm.target_kind = cv.target_kind AND vm.target_id = cv.target_id
    )
    UNION ALL
    -- the votes of a voter without vote changes in the window
    SELECT cv.voter_id, cv.target_kind, cv.target_id, 0, 0
    FROM current_votes cv
    WHERE NOT EXISTS (SELECT 1 FROM mark_counts mc WHERE mc.voter_id = cv.voter_id)
  ),
  voter_weights AS MATERIALIZED (
    SELECT w.account_id, w.vests
    FROM hafbe_backend.account_vest_stats_of(ARRAY(SELECT DISTINCT vr.voter_id FROM vote_rows vr)) w
  ),
  -- A vote change at the voter's weight then: its weight now minus every change of
  -- it after the vote (segments from the vote's own on).
  vote_values AS (
    SELECT
      vm.target_kind,
      vm.target_id,
      vm.voter_id,
      vm.cause,
      vm.approve,
      COALESCE(MAX(vw.vests), 0) - COALESCE(SUM(st.delta), 0) AS weight
    FROM vote_marks vm
    LEFT JOIN voter_weights vw ON vw.account_id = vm.voter_id
    LEFT JOIN segment_totals st ON st.voter_id = vm.voter_id AND st.seg >= vm.mark
    GROUP BY vm.target_kind, vm.target_id, vm.voter_id, vm.cause, vm.approve, vm.source_op
  ),
  contributions AS MATERIALIZED (
    SELECT c.target_kind, c.target_id, c.cause, c.voter_id, SUM(c.delta)::BIGINT AS delta
    FROM (
      SELECT b.target_kind, b.target_id, ss.cause, ss.voter_id, ss.delta
      FROM segment_sums ss
      JOIN backing b
        ON b.voter_id = ss.voter_id
        AND ss.seg BETWEEN b.seg_from AND b.seg_to
      UNION ALL
      SELECT
        vv.target_kind,
        vv.target_id,
        vv.cause,
        vv.voter_id,
        CASE WHEN vv.approve THEN vv.weight ELSE -vv.weight END
      FROM vote_values vv
    ) c
    GROUP BY c.target_kind, c.target_id, c.cause, c.voter_id
  )
  SELECT c.target_kind, c.target_id, c.cause, SUM(c.delta)::BIGINT, (COUNT(*) FILTER (WHERE c.delta <> 0))::INT
  FROM contributions c
  GROUP BY c.target_kind, c.target_id, c.cause
  UNION ALL
  SELECT c.target_kind, c.target_id, 'total', SUM(c.delta)::BIGINT, (COUNT(DISTINCT c.voter_id) FILTER (WHERE c.delta <> 0))::INT
  FROM contributions c
  GROUP BY c.target_kind, c.target_id;
END
$$;


/*
 * witness_votes_change_by_cause_of: votes_change_by_cause_of()'s witness rows, each
 * witness's vote change since _first_block by cause.
 */
CREATE OR REPLACE FUNCTION hafbe_app.witness_votes_change_by_cause_of(_first_block INT)
RETURNS TABLE (
    witness_id INT,
    cause      TEXT,
    vests      BIGINT,
    voters     INT
)
LANGUAGE sql STABLE
AS $$
  SELECT c.target_id, c.cause, c.vests, c.voters
  FROM hafbe_app.votes_change_by_cause_of(_first_block) c
  WHERE c.target_kind = 'witness'
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
 * last processed block, and written where they changed, with each witness's votes
 * and rank at each window's start (witness_votes_change_by_cause_start).
 *
 * The start votes are witness_votes_cache.votes minus the window's total, so the
 * cache must hold _block: single_processing() refreshes it in the transaction that
 * processes the block, so a snapshot that sees _block processed sees it too.
 * rank_start ranks every current witness as refresh_witness_rank_cache() ranks it
 * for rank, on the start values: votes, then voters_num (the cache's minus the
 * window's net approvals in witness_votes_history), then witness_id, all DESC. A
 * witness nothing moved in the window differs from its rank at _block only by the
 * moved witnesses that passed it.
 *
 * Raises when witness_votes_change_by_cause_indexes_ready() is false.
 */
CREATE OR REPLACE FUNCTION hafbe_app.refresh_witness_votes_change_by_cause(_block INT)
RETURNS VOID
LANGUAGE plpgsql VOLATILE
AS $$
DECLARE
  _today_first_block INT := hafbe_app.witness_votes_change_today_start(_block);
  _week_first_block  INT := hafbe_app.witness_votes_change_week_start(_block);
  _rows              JSONB;
BEGIN
  IF NOT hafbe_app.witness_votes_change_by_cause_indexes_ready() THEN
    RAISE EXCEPTION 'the balance tracker''s account_balance_history indexes are missing or invalid: restore its registered indexes (hive.app_restore_indexes) first';
  END IF;

  -- Each window computed once, for witnesses and proposals both (a few thousand rows,
  -- kept in a variable rather than a temporary table the session may not create).
  _rows := (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'time_window', x.time_window, 'target_kind', x.target_kind, 'target_id', x.target_id,
      'cause', x.cause, 'vests', x.vests, 'voters', x.voters)), '[]'::JSONB)
    FROM (
      SELECT 'today' AS time_window, c.target_kind, c.target_id, c.cause, c.vests, c.voters
      FROM hafbe_app.votes_change_by_cause_of(_today_first_block) c
      UNION ALL
      SELECT '7d', c.target_kind, c.target_id, c.cause, c.vests, c.voters
      FROM hafbe_app.votes_change_by_cause_of(_week_first_block) c
    ) x
  );

  MERGE INTO hafbe_app.witness_votes_change_by_cause t
  USING (
    SELECT r.target_id AS witness_id, r.time_window, r.cause, r.vests, r.voters
    FROM jsonb_to_recordset(_rows) AS r (time_window TEXT, target_kind TEXT, target_id INT, cause TEXT, vests BIGINT, voters INT)
    WHERE r.target_kind = 'witness'
  ) s ON t.witness_id = s.witness_id AND t.time_window = s.time_window AND t.cause = s.cause
  WHEN MATCHED AND (t.vests, t.voters) IS DISTINCT FROM (s.vests, s.voters) THEN
    UPDATE SET vests = s.vests, voters = s.voters
  WHEN NOT MATCHED THEN
    INSERT (witness_id, time_window, cause, vests, voters)
    VALUES (s.witness_id, s.time_window, s.cause, s.vests, s.voters)
  WHEN NOT MATCHED BY SOURCE THEN DELETE;

  MERGE INTO hafbe_app.witness_votes_change_by_cause_start t
  USING (
    SELECT
      x.witness_id,
      x.time_window,
      x.votes,
      (ROW_NUMBER() OVER (
        PARTITION BY x.time_window
        ORDER BY x.votes DESC, x.voters_num DESC, x.witness_id DESC
      ))::INT AS rank_start
    FROM (
      SELECT
        cw.witness_id,
        w.time_window,
        COALESCE(wv.votes, 0) - COALESCE(c.vests, 0) AS votes,
        COALESCE(wv.voters_num, 0)
          - COALESCE(CASE w.time_window WHEN 'today' THEN n.today ELSE n.week END, 0) AS voters_num
      FROM (VALUES ('today'), ('7d')) AS w (time_window)
      CROSS JOIN hafbe_app.current_witnesses cw
      LEFT JOIN hafbe_app.witness_votes_cache wv ON wv.witness_id = cw.witness_id
      LEFT JOIN hafbe_app.witness_votes_change_by_cause c
        ON c.witness_id = cw.witness_id
        AND c.time_window = w.time_window
        AND c.cause = 'total'
      -- The witness's net voters of each window, as voters_num_daily_change counts
      -- them. One scan from the 7-day window's start, which today's never precedes.
      LEFT JOIN (
        SELECT
          h.witness_id,
          SUM(CASE WHEN h.approve THEN 1 ELSE -1 END) FILTER (
            WHERE _today_first_block IS NOT NULL AND h.source_op >= hafd.operation_id(_today_first_block, 0)
          )::INT AS today,
          SUM(CASE WHEN h.approve THEN 1 ELSE -1 END)::INT AS week
        FROM hafbe_app.witness_votes_history h
        WHERE _week_first_block IS NOT NULL
          AND h.source_op >= hafd.operation_id(_week_first_block, 0)
        GROUP BY h.witness_id
      ) n ON n.witness_id = cw.witness_id
    ) x
  ) s ON t.witness_id = s.witness_id AND t.time_window = s.time_window
  WHEN MATCHED AND (t.votes, t.rank_start) IS DISTINCT FROM (s.votes, s.rank_start) THEN
    UPDATE SET votes = s.votes, rank_start = s.rank_start
  WHEN NOT MATCHED THEN
    INSERT (witness_id, time_window, votes, rank_start)
    VALUES (s.witness_id, s.time_window, s.votes, s.rank_start)
  WHEN NOT MATCHED BY SOURCE THEN DELETE;

  MERGE INTO hafbe_app.proposal_votes_change_by_cause t
  USING (
    SELECT r.target_id AS proposal_id, r.time_window, r.cause, r.vests, r.voters
    FROM jsonb_to_recordset(_rows) AS r (time_window TEXT, target_kind TEXT, target_id INT, cause TEXT, vests BIGINT, voters INT)
    WHERE r.target_kind = 'proposal'
  ) s ON t.proposal_id = s.proposal_id AND t.time_window = s.time_window AND t.cause = s.cause
  WHEN MATCHED AND (t.vests, t.voters) IS DISTINCT FROM (s.vests, s.voters) THEN
    UPDATE SET vests = s.vests, voters = s.voters
  WHEN NOT MATCHED THEN
    INSERT (proposal_id, time_window, cause, vests, voters)
    VALUES (s.proposal_id, s.time_window, s.cause, s.vests, s.voters)
  WHEN NOT MATCHED BY SOURCE THEN DELETE;

  -- Each proposal's votes at each window's start, and its place against the return
  -- proposal (id 0) then. hived pays the active proposals by total_votes, then
  -- proposal_id, both from the top, and the return proposal takes the rest of the
  -- budget (dhf_processor::sort_by_votes, transfer_payments): a proposal is above it
  -- with more votes, as a tie orders proposal 0 first (so one without votes is not
  -- either). Both are taken at the window's start: funded_start and gap_start are
  -- NULL for a proposal that had ended by then, for the return proposal itself, and
  -- when the return proposal had ended or is removed; a proposal not started yet then
  -- gets them, as where it would stand. A proposal created in the window counts as
  -- having had no votes at its start.
  MERGE INTO hafbe_app.proposal_votes_change_by_cause_start t
  USING (
    SELECT
      x.proposal_id,
      x.time_window,
      x.votes,
      CASE WHEN x.open AND x.proposal_id <> 0 THEN x.votes > r.votes END AS funded_start,
      CASE WHEN x.open AND x.proposal_id <> 0 THEN x.votes - r.votes END AS gap_start
    FROM (
      SELECT
        cp.proposal_id,
        w.time_window,
        COALESCE(ps.total_votes, 0) - COALESCE(c.vests, 0) AS votes,
        cp.end_date >= w.started_at AS open
      FROM (VALUES ('today', _today_first_block), ('7d', _week_first_block)) AS v (time_window, first_block)
      CROSS JOIN LATERAL (
        SELECT v.time_window, (SELECT b.created_at FROM hive.blocks_view b WHERE b.num = v.first_block) AS started_at
      ) w
      CROSS JOIN hafbe_app.current_proposals cp
      LEFT JOIN hafbe_app.proposal_vote_stats_cache ps ON ps.proposal_id = cp.proposal_id
      LEFT JOIN jsonb_to_recordset(_rows) AS c (time_window TEXT, target_kind TEXT, target_id INT, cause TEXT, vests BIGINT, voters INT)
        ON c.target_kind = 'proposal'
        AND c.target_id = cp.proposal_id
        AND c.time_window = w.time_window
        AND c.cause = 'total'
      WHERE NOT cp.removed
    ) x
    LEFT JOIN (
      SELECT
        w.time_window,
        COALESCE(ps.total_votes, 0) - COALESCE(c.vests, 0) AS votes
      FROM (VALUES ('today', _today_first_block), ('7d', _week_first_block)) AS v (time_window, first_block)
      CROSS JOIN LATERAL (
        SELECT v.time_window, (SELECT b.created_at FROM hive.blocks_view b WHERE b.num = v.first_block) AS started_at
      ) w
      JOIN hafbe_app.current_proposals cp
        ON cp.proposal_id = 0
        AND NOT cp.removed
        AND cp.end_date >= w.started_at
      LEFT JOIN hafbe_app.proposal_vote_stats_cache ps ON ps.proposal_id = 0
      LEFT JOIN jsonb_to_recordset(_rows) AS c (time_window TEXT, target_kind TEXT, target_id INT, cause TEXT, vests BIGINT, voters INT)
        ON c.target_kind = 'proposal'
        AND c.target_id = 0
        AND c.time_window = w.time_window
        AND c.cause = 'total'
    ) r ON r.time_window = x.time_window
  ) s ON t.proposal_id = s.proposal_id AND t.time_window = s.time_window
  WHEN MATCHED AND (t.votes, t.funded_start, t.gap_start) IS DISTINCT FROM (s.votes, s.funded_start, s.gap_start) THEN
    UPDATE SET votes = s.votes, funded_start = s.funded_start, gap_start = s.gap_start
  WHEN NOT MATCHED THEN
    INSERT (proposal_id, time_window, votes, funded_start, gap_start)
    VALUES (s.proposal_id, s.time_window, s.votes, s.funded_start, s.gap_start)
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
 * process_witness_votes_change_by_cause(_block): refreshes the breakdown for _block,
 * hafbe's last processed LIVE block, when one is due. The refresher session runs it
 * through refresh_witness_votes_change_by_cause_in_background(), outside block
 * processing (#211).
 *
 * Due 100 blocks (~5 minutes) after the last refresh, at the first block of a new UTC
 * day (_block's today window is not the stored one, so today follows
 * votes_daily_change's reset), and right away when nothing was refreshed yet or the
 * last refresh is above _block (a fork reverted it). Not at the last refresh's own
 * block: the refresher checks every few seconds, and a stalled chain would refresh on
 * each check. A fork that takes the chain back below as_of_block and returns to it
 * between two checks is not seen; its breakdown is replaced 100 blocks later. Skips
 * while the balance
 * tracker's indexes are not built yet (the first LIVE blocks), rather than scan its
 * history once per account, with a NOTICE the first time in the session.
 *
 * The breakdown is a display cache: a refresh that fails for any reason (an error, a
 * statement timeout, a cancel by request) is rolled back with a WARNING naming the
 * block and leaves the previous breakdown in place. The failed block is kept for the
 * session, and no refresh is attempted again until 100 blocks after it (or a fork
 * takes the chain back below it), whichever trigger asked: a refresh that keeps
 * failing would otherwise be retried, and paid for, on every check while as_of_block
 * stays NULL or ahead, or the chain stalls at the failed block.
 *
 * Bounded by the statement_timeout of the statement that calls it: in the refresher
 * session each check is a top-level statement of its own. Each refresh is logged with
 * its duration: a NOTICE, or a WARNING when it took longer than 10 s.
 */
CREATE OR REPLACE FUNCTION hafbe_app.process_witness_votes_change_by_cause(_block INT)
RETURNS VOID
LANGUAGE plpgsql VOLATILE
AS $$
DECLARE
  _state        hafbe_app.witness_votes_change_by_cause_state;
  _failed_block INT := NULLIF(current_setting('hafbe_app.witness_votes_change_by_cause_failed_block', TRUE), '')::INT;
  _started      TIMESTAMPTZ;
BEGIN
  SELECT * INTO _state FROM hafbe_app.witness_votes_change_by_cause_state;
  IF _state.as_of_block IS NULL OR _state.as_of_block > _block OR _block - _state.as_of_block >= 100
     OR _state.today_first_block IS DISTINCT FROM hafbe_app.witness_votes_change_today_start(_block) THEN
    IF _failed_block <= _block AND _block - _failed_block < 100 THEN
      RETURN;
    END IF;
    IF NOT hafbe_app.witness_votes_change_by_cause_indexes_ready() THEN
      IF current_setting('hafbe_app.witness_votes_change_by_cause_skip_noticed', TRUE) IS DISTINCT FROM 'on' THEN
        RAISE NOTICE 'witness_votes_change_by_cause: not refreshed from block % on until the balance tracker''s indexes are built', _block;
        PERFORM set_config('hafbe_app.witness_votes_change_by_cause_skip_noticed', 'on', FALSE);
      END IF;
      RETURN;
    END IF;
    _started := clock_timestamp();
    BEGIN
      PERFORM hafbe_app.refresh_witness_votes_change_by_cause(_block);
      PERFORM set_config('hafbe_app.witness_votes_change_by_cause_failed_block', '', FALSE);
    -- OTHERS does not cover query_canceled, which a statement timeout and a cancel raise.
    EXCEPTION WHEN OTHERS OR query_canceled THEN
      RAISE WARNING 'witness_votes_change_by_cause: refresh at block % failed, the previous breakdown (block %) stays, next attempt at block %: % (SQLSTATE %)',
        _block, _state.as_of_block, _block + 100, SQLERRM, SQLSTATE;
      PERFORM set_config('hafbe_app.witness_votes_change_by_cause_failed_block', _block::TEXT, FALSE);
      RETURN;
    END;
    IF clock_timestamp() - _started > INTERVAL '10 seconds' THEN
      RAISE WARNING 'witness_votes_change_by_cause: refresh at block % took % s',
        _block, round(extract(epoch FROM clock_timestamp() - _started)::NUMERIC, 1);
    ELSE
      RAISE NOTICE 'witness_votes_change_by_cause: refreshed at block % in % s',
        _block, round(extract(epoch FROM clock_timestamp() - _started)::NUMERIC, 1);
    END IF;
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


/*
 * refresh_witness_votes_change_by_cause_in_background(): one check of the refresher
 * session that scripts/process_blocks.sh runs beside block processing (#211):
 * process_witness_votes_change_by_cause() for the last block hafbe processed, so that
 * a slow refresh delays the breakdown, never a block.
 *
 * Must be called in a REPEATABLE READ transaction of its own. The refresh reads
 * hafbe's and the balance tracker's tables in several statements, which must all see
 * the same processed block: hive.app_next_iteration() sets the context's
 * current_block_num in the transaction that processes the block, so one snapshot
 * holds one block's state, the witness vote caches the start votes come from
 * included. Each CALL is a top-level statement, so the session's statement_timeout
 * bounds the refresh. The transaction reads hafd.contexts, so it enters HAF's contexts
 * gate first, as an application iteration does: hived's compaction of hafd.contexts
 * waits for it rather than queueing every application behind it.
 *
 * Does nothing unless the witness vote caches hold the context's current block
 * (witness_votes_cache_state): they are refreshed per block only in LIVE, so not
 * during the initial sync or a MASSIVE_PROCESSING catch-up, and HAF also commits a
 * current block nothing processed (a wait for HAF after a catch-up, a fork's rewind).
 */
CREATE OR REPLACE PROCEDURE hafbe_app.refresh_witness_votes_change_by_cause_in_background()
LANGUAGE plpgsql
AS $$
DECLARE
  _block INT;
BEGIN
  IF current_setting('transaction_isolation') <> 'repeatable read' THEN
    RAISE EXCEPTION 'refresh_witness_votes_change_by_cause_in_background() needs a REPEATABLE READ transaction of its own, not %',
      current_setting('transaction_isolation');
  END IF;
  IF to_regprocedure('hive.app_enter_contexts_gate()') IS NOT NULL THEN
    PERFORM hive.app_enter_contexts_gate();
  END IF;
  SELECT c.current_block_num INTO _block FROM hafd.contexts c WHERE c.name = 'hafbe_app';
  IF NOT EXISTS (SELECT 1 FROM hafbe_app.witness_votes_cache_state s WHERE s.block_num = _block) THEN
    RETURN;
  END IF;
  PERFORM hafbe_app.process_witness_votes_change_by_cause(_block);
END
$$;

RESET ROLE;
