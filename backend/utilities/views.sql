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
 * account_vest_stats_view: Complete vest statistics for witness voters.
 *
 * Calculates the total voting power for each account that has voted for
 * witnesses. Includes both the account's own vests and any vests being
 * proxied to them.
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
CREATE OR REPLACE VIEW hafbe_backend.account_vest_stats_view AS
SELECT
  cw.account_id,
  COALESCE(cab.balance::BIGINT, 0) - COALESCE(dv.delayed_vests::BIGINT, 0)
    + COALESCE(vpvv.proxied_vests, 0) AS vests,
  COALESCE(cab.balance::BIGINT, 0) - COALESCE(dv.delayed_vests::BIGINT, 0) AS account_vests,
  COALESCE(vpvv.proxied_vests, 0) AS proxied_vests
FROM hafbe_backend.witness_voters_list_view cw
LEFT JOIN current_account_balances cab
  ON cab.account = cw.account_id
  AND cab.nai = btracker_backend.nai_vests()
LEFT JOIN hafbe_backend.voters_proxied_vests_sum_view vpvv ON vpvv.proxy_id = cw.account_id
LEFT JOIN account_withdraws dv ON dv.account = cw.account_id;

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

RESET ROLE;
