SET ROLE hafbe_owner;

-- ============================================================================
-- Backend Views
-- ============================================================================
-- Views used by API endpoints to provide pre-joined and calculated data.
-- These views simplify endpoint queries by encapsulating complex joins and
-- calculations that are commonly needed.
--
-- MAIN COMPONENTS:
--   1. Witness Operation Views - For witness page endpoints
--   2. Proxy Views - For vote proxy calculations
--   3. Vest Calculation Views - For voting power calculations
--   4. Time Logging Views - For sync performance monitoring
--   5. History Views - For vote/proxy history endpoints
--
-- DESIGN PATTERN:
--   Views use LEFT JOINs to handle missing data gracefully.
--   COALESCE is used to provide sensible defaults (usually 0) for NULL values.
-- ============================================================================

-- ============================================================================
-- SECTION 1: Witness Operation Views
-- ============================================================================

/*
 * witness_prop_op_view: Extracts witness property operations with impacted accounts.
 *
 * Used by witness page endpoints to display witness-related operations
 * with the witness name resolved from the operation's impacted accounts.
 *
 * COLUMNS:
 *   witness      - The witness account name (from impacted accounts)
 *   value        - The operation value as JSONB
 *   body_value   - Operation value as JSONB (inner value only, no type wrapper)
 *   block_num    - Block number of the operation
 *   op_type_id   - Operation type ID
 *   operation_id - Unique operation ID
 */
CREATE OR REPLACE VIEW hafbe_backend.witness_prop_op_view AS
SELECT
  bia.name AS witness,
  ov.body_value AS value,
  ov.block_num,
  ov.op_type_id,
  ov.id AS operation_id
FROM hafbe_app.operations_view ov
JOIN LATERAL (
  SELECT get_impacted_accounts AS name
  FROM hive.get_impacted_accounts(ov.body::hafd.operation)
) bia ON TRUE;

-- ============================================================================
-- SECTION 2: Proxy Views
-- ============================================================================

/*
 * recursive_account_proxies_view: Calculates the proxy chain up to 4 levels deep.
 *
 * Hive allows accounts to proxy their voting power through a chain of up to
 * 4 accounts. This view unrolls that chain so we can calculate total proxied
 * voting power for each proxy account.
 *
 * COLUMNS:
 *   proxy_id    - The account receiving the proxied votes (top-level proxy)
 *   account_id  - The account whose votes are being proxied
 *   proxy_level - How many levels deep (1 = direct proxy, 4 = max depth)
 *
 * DATA FLOW:
 *   Level 1: A -> B (A proxies to B)
 *   Level 2: A -> B -> C (A proxied to B, which proxies to C)
 *   Level 3: A -> B -> C -> D
 *   Level 4: A -> B -> C -> D -> E (maximum depth)
 */
CREATE OR REPLACE VIEW hafbe_backend.recursive_account_proxies_view AS
WITH proxies1 AS (
  SELECT
    prox1.proxy_id AS top_proxy_id,
    prox1.account_id,
    1 AS proxy_level
  FROM hafbe_app.current_account_proxies prox1
),
proxies2 AS (
  SELECT
    prox1.top_proxy_id,
    prox2.account_id,
    2 AS proxy_level
  FROM proxies1 prox1
  JOIN hafbe_app.current_account_proxies prox2 ON prox2.proxy_id = prox1.account_id
),
proxies3 AS (
  SELECT
    prox2.top_proxy_id,
    prox3.account_id,
    3 AS proxy_level
  FROM proxies2 prox2
  JOIN hafbe_app.current_account_proxies prox3 ON prox3.proxy_id = prox2.account_id
),
proxies4 AS (
  SELECT
    prox3.top_proxy_id,
    prox4.account_id,
    4 AS proxy_level
  FROM proxies3 prox3
  JOIN hafbe_app.current_account_proxies prox4 ON prox4.proxy_id = prox3.account_id
)
SELECT
  top_proxy_id AS proxy_id,
  account_id,
  proxy_level
FROM (
  SELECT top_proxy_id, account_id, proxy_level FROM proxies1
  UNION
  SELECT top_proxy_id, account_id, proxy_level FROM proxies2
  UNION
  SELECT top_proxy_id, account_id, proxy_level FROM proxies3
  UNION
  SELECT top_proxy_id, account_id, proxy_level FROM proxies4
) rap;

/*
 * witness_voters_list_view: List of accounts that have voted for any witness.
 *
 * Used as the basis for calculating voting power - only accounts that have
 * actually cast witness votes are included.
 *
 * COLUMNS:
 *   account_id - Account ID of the voter
 */
CREATE OR REPLACE VIEW hafbe_backend.witness_voters_list_view AS
SELECT cwv.voter_id AS account_id
FROM hafbe_app.current_witness_votes cwv
GROUP BY cwv.voter_id;

-- ============================================================================
-- SECTION 3: Vest Calculation Views
-- ============================================================================

/*
 * voters_proxied_vests_view: Calculates proxied vests per proxy level.
 *
 * For each proxy account, calculates how many vests are being proxied to it
 * at each level of the proxy chain. This is used to break down voting power
 * by proxy depth.
 *
 * COLUMNS:
 *   proxy_id     - The proxy account ID
 *   proxied_vests - Total vests proxied at this level
 *   proxy_level  - The proxy chain depth (1-4)
 *
 * CALCULATION:
 *   proxied_vests = SUM(balance - delayed_vests) for all accounts at this level
 *   delayed_vests accounts for vesting withdrawals in progress
 */
CREATE OR REPLACE VIEW hafbe_backend.voters_proxied_vests_view AS
SELECT
  rapv.proxy_id,
  SUM(cab.balance - COALESCE(dv.delayed_vests, 0))::BIGINT AS proxied_vests,
  rapv.proxy_level
FROM hafbe_backend.recursive_account_proxies_view rapv
JOIN current_account_balances cab
  ON cab.account = rapv.account_id
  AND cab.nai = btracker_backend.nai_vests()
LEFT JOIN account_withdraws dv ON dv.account = rapv.account_id
GROUP BY rapv.proxy_id, rapv.proxy_level;

/*
 * voters_proxied_vests_sum_view: Calculates total proxied vests for each proxy.
 *
 * Sums up all vests being proxied to an account across all proxy levels.
 * This is the total voting power an account controls via proxies.
 *
 * COLUMNS:
 *   proxy_id      - The proxy account ID
 *   proxied_vests - Total vests proxied from all levels combined
 */
CREATE OR REPLACE VIEW hafbe_backend.voters_proxied_vests_sum_view AS
SELECT
  rapv.proxy_id,
  SUM(cab.balance - COALESCE(dv.delayed_vests, 0))::BIGINT AS proxied_vests
FROM hafbe_backend.recursive_account_proxies_view rapv
JOIN current_account_balances cab
  ON cab.account = rapv.account_id
  AND cab.nai = btracker_backend.nai_vests()
LEFT JOIN account_withdraws dv ON dv.account = rapv.account_id
GROUP BY rapv.proxy_id;

/*
 * account_vest_stats: Complete vest statistics for accounts whose vesting
 * power the API needs to report.
 *
 * Covers four groups (not disjoint — a single account may be in several, e.g.
 * casting both witness and proposal votes):
 *   - direct witness voters   (used by get_witness_voters)
 *   - proxy setters           (used by get_account_proxies_power)
 *   - direct proposal voters  (used by proposal_vote_stats_cache refresh)
 *   - voters with a witness vote event at or after _first_block_num
 *     (used by witness_votes_change_cache — the "gained/lost votes" columns)
 *
 * UNION (not UNION ALL) is required: an account appearing in two groups
 * must collapse to a single row, otherwise downstream SUM(vests)
 * aggregations double-count them. The fourth branch overlaps the first
 * heavily, so this matters more than it used to.
 *
 * WHY THE FOURTH BRANCH (issue #142). The first three cover only CURRENT
 * participants, but Cache 4 of process_witness_votes_cache() aggregates over
 * HISTORY — a strict superset. A voter whose LAST witness vote was removed
 * inside the window has left all three sets, so it had no row here and Cache
 * 4's INNER JOIN silently dropped its -1 / -vests: gains were counted, losses
 * vanished (block_explorer_ui#743). Two of the three removal paths produce that
 * shape — an approve=FALSE history row for an account just deleted from
 * current_witness_votes: an explicit un-vote, and the declined_voting_rights /
 * expired_account_notification cascade in process_expired_accounts (which drops ALL
 * of the account's votes at once). The proxy cascade in process_proxy_ops was NOT
 * affected: it upserts current_account_proxies in the same call, so the second
 * branch above already covered those accounts. Including the rest here makes that
 * join lossless BY CONSTRUCTION.
 *
 * WHY IT IS WINDOW-BOUNDED. Bounding the branch to the same window Cache 4
 * aggregates keeps growth proportional to daily churn instead of to all of
 * history. This whole result is re-materialised into account_vest_stats_cache
 * on EVERY LIVE block (~3 s), so unbounded growth would be paid forever.
 *
 * WHY A FUNCTION AND NOT A VIEW. Cache 1 and Cache 4 must aggregate over the
 * same window or the INNER JOIN stops being total; a view cannot take that
 * window as an argument, and re-deriving it inside the view body would let the
 * two drift between statements (they straddle midnight otherwise).
 * Note the consequence: a view body binds relation names at CREATE time (which
 * is how install_app.sh pins the unqualified btracker relations below via
 * SET SEARCH_PATH), whereas a function body resolves them at EXECUTION time,
 * against the caller's search_path. That is already a hard requirement for any
 * vest query — btracker_backend.nai_vests() reads `asset_table` unqualified and
 * carries no SET search_path — so every caller that works today already sets it
 * (scripts/process_blocks.sh, scripts/prepare_mock_cache.sh,
 * PGRST_DB_EXTRA_SEARCH_PATH).
 *
 * PARAMETERS:
 *   _first_block_num - inclusive lower bound, as a block number, on the witness
 *                      vote events considered by the fourth branch. 0 = all of
 *                      history.
 *
 * COLUMNS:
 *   account_id    - The account ID
 *   vests         - Total voting power (own + proxied)
 *   account_vests - Account's own vesting shares (minus pending withdrawals)
 *   proxied_vests - Vests being proxied to this account
 *
 * CALCULATION:
 *   vests = account_vests + proxied_vests
 *   account_vests = balance - delayed_vests
 */
-- Superseded by the function below; dropped so upgraded databases do not keep a
-- stale copy that silently omits the fourth group.
DROP VIEW IF EXISTS hafbe_backend.account_vest_stats_view;

CREATE OR REPLACE FUNCTION hafbe_backend.account_vest_stats(_first_block_num INT)
RETURNS TABLE (
    account_id    INT,
    vests         BIGINT,
    account_vests BIGINT,
    proxied_vests BIGINT
)
-- LANGUAGE sql, and deliberately WITHOUT SET clauses: a single-SELECT sql function
-- is inlinable, so this is flattened into the caller's INSERT ... SELECT exactly as
-- the view it replaced was. A plpgsql body would buffer every row through a
-- tuplestore on each LIVE block and report a fixed 1000-row estimate; any SET clause
-- here would block inlining too. The only caller already sets all three
-- (db/process_witness_votes.sql), and they apply to the flattened statement.
LANGUAGE sql STABLE
AS
$$
    WITH tracked_accounts AS (
      SELECT twv.account_id FROM hafbe_backend.witness_voters_list_view twv
      UNION
      SELECT tap.account_id FROM hafbe_app.current_account_proxies tap
      UNION
      SELECT tpv.voter_id AS account_id FROM hafbe_app.current_proposal_votes tpv
      UNION
      -- Compared against source_op rather than the decoded block number so the
      -- predicate stays sargable: hafd.operation_id(b, 0) is the minimum
      -- operation id in block b, and witness_votes_history carries a BRIN index
      -- on source_op. Decoding per row (operation_id_to_block_num) would force a
      -- seq scan of a forever-growing table on every LIVE block.
      --
      -- The IS NOT NULL guard is load-bearing: hafd.operation_id is a non-STRICT C
      -- function that reads a NULL block number as 0, so without it a NULL window
      -- (a chain whose genesis is after today's midnight, or an unprocessed context)
      -- would silently widen this branch to ALL of history instead of matching
      -- nothing, which is what the old `source_op_block >= NULL` did.
      SELECT twh.voter_id AS account_id
      FROM hafbe_app.witness_votes_history twh
      WHERE _first_block_num IS NOT NULL
        AND twh.source_op >= hafd.operation_id(_first_block_num, 0)
    )
    SELECT
      cw.account_id,
      COALESCE(cab.balance::BIGINT, 0) - COALESCE(dv.delayed_vests::BIGINT, 0)
        + COALESCE(vpvv.proxied_vests, 0) AS vests,
      COALESCE(cab.balance::BIGINT, 0) - COALESCE(dv.delayed_vests::BIGINT, 0) AS account_vests,
      COALESCE(vpvv.proxied_vests, 0) AS proxied_vests
    FROM tracked_accounts cw
    LEFT JOIN current_account_balances cab
      ON cab.account = cw.account_id
      AND cab.nai = btracker_backend.nai_vests()
    LEFT JOIN hafbe_backend.voters_proxied_vests_sum_view vpvv ON vpvv.proxy_id = cw.account_id
    LEFT JOIN account_withdraws dv ON dv.account = cw.account_id
$$;

-- proposal_paid_amounts view removed: paid_amount is now a running total column
-- on hafbe_app.current_proposals, updated by process_proposal_pay_op. Endpoints
-- read cp.paid_amount directly; proposal_payments stays as an audit ledger.

/*
 * expired_voter_stats_view: Vest stats for voters not in current voter list.
 *
 * Helper view for hafbe_backend.get_witness_votes_history to calculate vest
 * stats for voters that are no longer active (not in witness_voters_list_view)
 * but have historical vote data.
 *
 * COLUMNS:
 *   account_id    - The account ID
 *   vests         - Total voting power (own + proxied)
 *   account_vests - Account's own vesting shares
 *   proxied_vests - Vests being proxied to this account
 *
 * NOTE: Uses hive.accounts_view to include all accounts, not just active voters.
 */
CREATE OR REPLACE VIEW hafbe_backend.expired_voter_stats_view AS
SELECT
  av.id AS account_id,
  COALESCE(cab.balance::BIGINT, 0) - COALESCE(dv.delayed_vests::BIGINT, 0)
    + COALESCE(vpvv.proxied_vests, 0) AS vests,
  COALESCE(cab.balance::BIGINT, 0) - COALESCE(dv.delayed_vests::BIGINT, 0) AS account_vests,
  COALESCE(vpvv.proxied_vests, 0) AS proxied_vests
FROM hive.accounts_view av
LEFT JOIN current_account_balances cab
  ON cab.account = av.id
  AND cab.nai = btracker_backend.nai_vests()
LEFT JOIN hafbe_backend.voters_proxied_vests_sum_view vpvv ON vpvv.proxy_id = av.id
LEFT JOIN account_withdraws dv ON dv.account = av.id;

-- ============================================================================
-- SECTION 4: Time Logging Views
-- ============================================================================

/*
 * time_logs_view: Provides easy access to sync timing data.
 *
 * Allows searching through timing data for each section of hafbe sync.
 * Used for performance monitoring and optimization.
 *
 * COLUMNS:
 *   block_num      - Block number being processed
 *   hafbe          - Time spent in HAFBE processing (seconds)
 *   btracker       - Time spent in Balance Tracker processing (seconds)
 *   state_provider - Time spent in state provider operations (seconds)
 */
CREATE OR REPLACE VIEW hafbe_backend.time_logs_view AS
SELECT
  block_num,
  (time_json ->> 'hafbe')::NUMERIC AS hafbe,
  (time_json ->> 'btracker')::NUMERIC AS btracker,
  (time_json ->> 'state_provider')::NUMERIC AS state_provider
FROM hafbe_app.sync_time_logs;

-- ============================================================================
-- SECTION 5: History Views
-- ============================================================================
-- Views that wrap history tables and extract block numbers from operation IDs.
-- These avoid storing redundant block_num columns by computing them on-the-fly.
-- ============================================================================

/*
 * witness_votes_history_view: Witness vote history with computed block numbers.
 *
 * Wraps hafbe_app.witness_votes_history and extracts block_num and op_type_id
 * from the source_op operation ID using HAF helper functions.
 *
 * COLUMNS:
 *   witness_id      - The witness being voted for
 *   voter_id        - The account casting the vote
 *   approve         - TRUE for vote, FALSE for unvote
 *   source_op       - The operation ID that caused this change
 *   source_op_block - Block number extracted from source_op
 *   op_type_id      - Operation type extracted from source_op
 */
CREATE OR REPLACE VIEW hafbe_backend.witness_votes_history_view AS
SELECT
  t.witness_id,
  t.voter_id,
  t.approve,
  t.source_op,
  hafd.operation_id_to_block_num(t.source_op) AS source_op_block,
  (SELECT ops.op_type_id FROM hafd.operations ops WHERE ops.id = t.source_op) AS op_type_id
FROM hafbe_app.witness_votes_history t;

/*
 * current_witness_votes_view: Current witness votes with computed block numbers.
 *
 * Wraps hafbe_app.current_witness_votes and extracts block_num and op_type_id
 * from the source_op operation ID.
 *
 * COLUMNS:
 *   voter_id        - The account that cast the vote
 *   witness_id      - The witness being voted for
 *   source_op       - The operation ID of the vote
 *   source_op_block - Block number extracted from source_op
 *   op_type_id      - Operation type extracted from source_op
 */
CREATE OR REPLACE VIEW hafbe_backend.current_witness_votes_view AS
SELECT
  t.voter_id,
  t.witness_id,
  t.source_op,
  hafd.operation_id_to_block_num(t.source_op) AS source_op_block,
  (SELECT ops.op_type_id FROM hafd.operations ops WHERE ops.id = t.source_op) AS op_type_id
FROM hafbe_app.current_witness_votes t;

/*
 * account_proxies_history_view: Proxy change history with computed block numbers.
 *
 * Wraps hafbe_app.account_proxies_history and extracts block_num and op_type_id
 * from the source_op operation ID.
 *
 * COLUMNS:
 *   account_id      - The account setting/clearing the proxy
 *   proxy_id        - The account being proxied to (NULL if clearing)
 *   proxy           - TRUE if setting proxy, FALSE if clearing
 *   source_op       - The operation ID that caused this change
 *   source_op_block - Block number extracted from source_op
 *   op_type_id      - Operation type extracted from source_op
 */
CREATE OR REPLACE VIEW hafbe_backend.account_proxies_history_view AS
SELECT
  t.account_id,
  t.proxy_id,
  t.proxy,
  t.source_op,
  hafd.operation_id_to_block_num(t.source_op) AS source_op_block,
  (SELECT ops.op_type_id FROM hafd.operations ops WHERE ops.id = t.source_op) AS op_type_id
FROM hafbe_app.account_proxies_history t;

/*
 * current_account_proxies_view: Current proxy settings with computed block numbers.
 *
 * Wraps hafbe_app.current_account_proxies and extracts block_num and op_type_id
 * from the source_op operation ID.
 *
 * COLUMNS:
 *   account_id      - The account that set the proxy
 *   proxy_id        - The account being proxied to
 *   source_op       - The operation ID of the proxy setting
 *   source_op_block - Block number extracted from source_op
 *   op_type_id      - Operation type extracted from source_op
 */
CREATE OR REPLACE VIEW hafbe_backend.current_account_proxies_view AS
SELECT
  t.account_id,
  t.proxy_id,
  t.source_op,
  hafd.operation_id_to_block_num(t.source_op) AS source_op_block,
  (SELECT ops.op_type_id FROM hafd.operations ops WHERE ops.id = t.source_op) AS op_type_id
FROM hafbe_app.current_account_proxies t;


/*
 * proposal_votes_history_view: Proposal vote history with computed block numbers.
 *
 * Wraps hafbe_app.proposal_votes_history and extracts block_num and op_type_id
 * from the source_op operation ID using HAF helper functions.
 */
CREATE OR REPLACE VIEW hafbe_backend.proposal_votes_history_view AS
SELECT
  t.proposal_id,
  t.voter_id,
  t.approve,
  t.source_op,
  hafd.operation_id_to_block_num(t.source_op) AS source_op_block,
  (SELECT ops.op_type_id FROM hafd.operations ops WHERE ops.id = t.source_op) AS op_type_id
FROM hafbe_app.proposal_votes_history t;

RESET ROLE;
