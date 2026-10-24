-- =============================================================================
-- HAF Block Explorer Regression Test - Comparison Functions
-- =============================================================================
--
-- PURPOSE:
--   Functions to compare HAF Block Explorer's computed values against expected
--   values loaded from hived snapshots.
--
-- COMPARISON STRATEGY:
--   1. Load expected values from hafbe_test.expected_* tables
--   2. Query computed values directly from hafbe_app.* tables
--   3. Compare field by field with appropriate NULL handling
--   4. Insert differing IDs into hafbe_test.differing_* tables
--
-- FUNCTIONS:
--   hafbe_test.compare_accounts()           - Compare all accounts
--   hafbe_test.compare_witnesses()          - Compare all witnesses
--   hafbe_test.compare_wallet_stats()       - Compare wallet_stats_by_day with account_parameters
--   hafbe_test.compare_account_ops_count()  - Compare account_ops_count with account_operations
--   hafbe_test.get_account_comparison(int)  - Debug helper for single account
--   hafbe_test.get_witness_comparison(int)  - Debug helper for single witness
--
-- =============================================================================

SET ROLE hafbe_owner;

-- =============================================================================
-- Account Comparison
-- =============================================================================

/*
 * compare_accounts: Compare all accounts against expected values.
 *
 * Queries hafbe_app tables directly and compares with expected_account_stats.
 * Accounts with ID <= 4 are skipped (system accounts).
 *
 * DATA SOURCES:
 *   - witnesses_voted_for: COUNT from hafbe_app.current_witness_votes
 *   - can_vote, mined, last_account_recovery, created, recovery_account:
 *     from hafbe_app.account_parameters
 *   - proxy: from hafbe_app.current_account_proxies
 *
 * OUTPUT: Inserts differing account_ids into hafbe_test.differing_accounts
 */
CREATE OR REPLACE FUNCTION hafbe_test.compare_accounts()
RETURNS VOID
LANGUAGE plpgsql VOLATILE
AS $$
BEGIN
  RAISE NOTICE 'Comparing hafbe account stats with expected values...';

  /*
   * ==========================================================================
   * CTE: expected_accounts
   * ==========================================================================
   * WHY MATERIALIZED: Source data scanned once, used by comparison JOIN.
   */
  WITH expected_accounts AS MATERIALIZED (
    SELECT
      account_id,
      witnesses_voted_for,
      can_vote,
      mined,
      last_account_recovery,
      created,
      proxy,
      recovery_account
    FROM hafbe_test.expected_account_stats
  ),

  /*
   * ==========================================================================
   * CTE: computed_witnesses_voted
   * ==========================================================================
   * WHY MATERIALIZED: Aggregation result used once.
   * PURPOSE: Count witness votes per account from hafbe_app.
   */
  computed_witnesses_voted AS MATERIALIZED (
    SELECT
      cwv.voter_id AS account_id,
      COUNT(*)::INT AS witnesses_voted_for
    FROM hafbe_app.current_witness_votes cwv
    GROUP BY cwv.voter_id
  ),

  /*
   * ==========================================================================
   * CTE: computed_params
   * ==========================================================================
   * WHY MATERIALIZED: Table scan used once.
   * PURPOSE: Get account parameters from hafbe_app.
   */
  computed_params AS MATERIALIZED (
    SELECT
      ap.account AS account_id,
      ap.can_vote,
      ap.mined,
      ap.last_account_recovery,
      ap.created,
      ap.recovery_account
    FROM hafbe_app.account_parameters ap
  ),

  /*
   * ==========================================================================
   * CTE: computed_proxies
   * ==========================================================================
   * WHY MATERIALIZED: Table scan used once.
   * PURPOSE: Get proxy settings from hafbe_app.
   */
  computed_proxies AS MATERIALIZED (
    SELECT account_id, proxy_id
    FROM hafbe_app.current_account_proxies
  ),

  /*
   * ==========================================================================
   * CTE: comparison
   * ==========================================================================
   * PURPOSE: Join expected and computed values for comparison.
   *
   * DEFAULT VALUES (matching hafbe_backend constants):
   *   - witnesses_voted_for: 0 (no votes)
   *   - can_vote: TRUE (default_can_vote)
   *   - mined: TRUE (default_mined)
   *   - timestamps: '1970-01-01T00:00:00' (default_timestamp)
   *   - recovery_account: '' (default_recovery_account)
   *   - proxy: NULL (no proxy)
   */
  comparison AS MATERIALIZED (
    SELECT
      ea.account_id,
      -- Expected values
      ea.witnesses_voted_for   AS exp_witnesses_voted_for,
      ea.can_vote              AS exp_can_vote,
      ea.mined                 AS exp_mined,
      ea.last_account_recovery AS exp_last_account_recovery,
      ea.created               AS exp_created,
      ea.proxy                 AS exp_proxy,
      ea.recovery_account      AS exp_recovery_account,
      -- Computed values with defaults
      COALESCE(cwv.witnesses_voted_for, 0)                            AS cur_witnesses_voted_for,
      COALESCE(cp.can_vote, TRUE)                                     AS cur_can_vote,
      COALESCE(cp.mined, TRUE)                                        AS cur_mined,
      COALESCE(cp.last_account_recovery, '1970-01-01T00:00:00')       AS cur_last_account_recovery,
      COALESCE(cp.created, '1970-01-01T00:00:00')                     AS cur_created,
      cpx.proxy_id                                                    AS cur_proxy,
      COALESCE(cp.recovery_account, '')                               AS cur_recovery_account
    FROM expected_accounts ea
    LEFT JOIN computed_witnesses_voted cwv ON cwv.account_id = ea.account_id
    LEFT JOIN computed_params cp ON cp.account_id = ea.account_id
    LEFT JOIN computed_proxies cpx ON cpx.account_id = ea.account_id
  )

  /*
   * INSERT DIFFERENCES:
   * Skip system accounts (id <= 4).
   * Use IS DISTINCT FROM for proxy (nullable comparison).
   */
  INSERT INTO hafbe_test.differing_accounts (account_id)
  SELECT account_id
  FROM comparison
  WHERE account_id > 4
    AND (
      exp_witnesses_voted_for   != cur_witnesses_voted_for
      OR exp_can_vote           != cur_can_vote
      OR exp_mined              != cur_mined
      OR exp_last_account_recovery != cur_last_account_recovery
      OR exp_created            != cur_created
      OR exp_proxy IS DISTINCT FROM cur_proxy
      OR exp_recovery_account   != cur_recovery_account
    );

  RAISE NOTICE 'Account comparison complete.';
END
$$;

-- =============================================================================
-- Witness Comparison
-- =============================================================================

/*
 * compare_witnesses: Compare all witnesses against expected values.
 *
 * Queries hafbe_app.current_witnesses and current_witness_votes directly.
 * Witnesses with ID <= 4 are skipped (system accounts).
 *
 * DATA SOURCES:
 *   - url, signing_key, version, price_feed, etc: from current_witnesses
 *   - vests: SUM of voter vesting shares from witness votes
 *   - last_confirmed_block_num: mapped from last_created_block_num
 *
 * TIMESTAMP TOLERANCE:
 *   - created: 66-second tolerance (block time vs operation time difference)
 *
 * OUTPUT: Inserts differing witness_ids into hafbe_test.differing_witnesses
 */
CREATE OR REPLACE FUNCTION hafbe_test.compare_witnesses()
RETURNS VOID
LANGUAGE plpgsql VOLATILE
AS $$
BEGIN
  RAISE NOTICE 'Comparing hafbe witness props with expected values...';

  /*
   * ==========================================================================
   * CTE: expected_witnesses
   * ==========================================================================
   * WHY MATERIALIZED: Source data scanned once, used by comparison JOIN.
   */
  WITH expected_witnesses AS MATERIALIZED (
    SELECT
      witness_id,
      url,
      vests,
      missed_blocks,
      last_confirmed_block_num,
      signing_key,
      version,
      account_creation_fee,
      block_size,
      hbd_interest_rate,
      price_feed,
      feed_updated_at,
      created
    FROM hafbe_test.expected_witness_props
  ),

  /*
   * ==========================================================================
   * CTE: computed_vests
   * ==========================================================================
   * WHY MATERIALIZED: Table scan used once.
   *
   * PURPOSE: Get pre-computed witness votes from cache.
   *
   * Note: witness_votes_cache is populated by update_witness_cache()
   * and contains total vesting shares voting for each witness.
   */
  computed_vests AS MATERIALIZED (
    SELECT
      wvc.witness_id,
      wvc.votes AS vests
    FROM hafbe_app.witness_votes_cache wvc
  ),

  /*
   * ==========================================================================
   * CTE: computed_witnesses
   * ==========================================================================
   * WHY MATERIALIZED: Table scan used once.
   *
   * PURPOSE: Get witness properties from hafbe_app.current_witnesses.
   *
   * FIELD MAPPING:
   *   - last_created_block_num -> last_confirmed_block_num
   *   - price_feed stored as DOUBLE PRECISION, cast to NUMERIC
   */
  computed_witnesses AS MATERIALIZED (
    SELECT
      cw.witness_id,
      cw.url,
      cw.missed_blocks,
      cw.last_created_block_num AS last_confirmed_block_num,
      cw.signing_key,
      cw.version,
      cw.account_creation_fee,
      cw.block_size,
      cw.hbd_interest_rate,
      cw.price_feed::NUMERIC AS price_feed,
      cw.feed_updated_at,
      cw.created
    FROM hafbe_app.current_witnesses cw
  ),

  /*
   * ==========================================================================
   * CTE: comparison
   * ==========================================================================
   * PURPOSE: Join expected and computed values for comparison.
   */
  comparison AS MATERIALIZED (
    SELECT
      ew.witness_id,
      -- Expected values
      ew.url                    AS exp_url,
      ew.vests                  AS exp_vests,
      ew.missed_blocks          AS exp_missed_blocks,
      ew.last_confirmed_block_num AS exp_last_confirmed_block_num,
      ew.signing_key            AS exp_signing_key,
      ew.version                AS exp_version,
      ew.account_creation_fee   AS exp_account_creation_fee,
      ew.block_size             AS exp_block_size,
      ew.hbd_interest_rate      AS exp_hbd_interest_rate,
      ew.price_feed             AS exp_price_feed,
      ew.feed_updated_at        AS exp_feed_updated_at,
      ew.created                AS exp_created,
      -- Computed values
      cw.url                    AS cur_url,
      COALESCE(cv.vests, 0)     AS cur_vests,
      cw.missed_blocks          AS cur_missed_blocks,
      cw.last_confirmed_block_num AS cur_last_confirmed_block_num,
      cw.signing_key            AS cur_signing_key,
      cw.version                AS cur_version,
      cw.account_creation_fee   AS cur_account_creation_fee,
      cw.block_size             AS cur_block_size,
      cw.hbd_interest_rate      AS cur_hbd_interest_rate,
      cw.price_feed             AS cur_price_feed,
      cw.feed_updated_at        AS cur_feed_updated_at,
      cw.created                AS cur_created
    FROM expected_witnesses ew
    LEFT JOIN computed_witnesses cw ON cw.witness_id = ew.witness_id
    LEFT JOIN computed_vests cv ON cv.witness_id = ew.witness_id
  )

  /*
   * INSERT DIFFERENCES:
   * Skip system accounts (id <= 4).
   *
   * TIMESTAMP TOLERANCE FOR CREATED AND FEED_UPDATED_AT:
   *   hived uses operation timestamp (from transaction),
   *   hafbe uses block timestamp (from blocks_view).
   *
   *   Normally these differ by ~3 seconds (one block time).
   *   However, when a witness misses their block, the gap can be up to
   *   63 seconds (21 witnesses × 3 seconds = full round).
   *
   *   Example: Witness "stranger" at block 815424 has 63-second gap
   *   because block 815424 was produced 63 seconds after 815423.
   *
   *   We use 66-second tolerance (63 + 3 buffer) to handle these cases.
   *   This applies to both 'created' and 'feed_updated_at' timestamps.
   */
  INSERT INTO hafbe_test.differing_witnesses (witness_id)
  SELECT witness_id
  FROM comparison
  WHERE witness_id > 4
    AND (
      exp_url                    != cur_url
      OR exp_vests               != cur_vests
      OR exp_missed_blocks       != cur_missed_blocks
      OR exp_last_confirmed_block_num != cur_last_confirmed_block_num
      OR exp_signing_key         != cur_signing_key
      -- version: NULL or empty treated as equivalent to '0.0.0' (default in hived)
      OR COALESCE(NULLIF(exp_version, '0.0.0'), '') != COALESCE(cur_version, '')
      OR exp_account_creation_fee != cur_account_creation_fee
      OR exp_block_size          != cur_block_size
      OR exp_hbd_interest_rate   != cur_hbd_interest_rate
      -- price_feed: Allow small floating point tolerance (1e-10)
      OR ABS(exp_price_feed - cur_price_feed) > 1e-10
      -- feed_updated_at: Same 66-second tolerance as created (block vs operation timestamp)
      OR ABS(EXTRACT(EPOCH FROM (exp_feed_updated_at - cur_feed_updated_at))) > 66
      OR ABS(EXTRACT(EPOCH FROM (exp_created - cur_created))) > 66
    );

  RAISE NOTICE 'Witness comparison complete.';
END
$$;

-- =============================================================================
-- Wallet Statistics Comparison
-- =============================================================================

/*
 * compare_wallet_stats: Compare hafbe_app.wallet_stats_by_day with the same
 * aggregate recomputed from hafbe_app.account_parameters.
 *
 * Holds at any block the context is at: after massive sync, after LIVE blocks
 * and after a fork rollback, since both tables are reverted together.
 * Unlike the other comparisons it needs no hived snapshot.
 *
 * OUTPUT: Inserts differing days into hafbe_test.differing_wallet_days
 */
CREATE OR REPLACE FUNCTION hafbe_test.compare_wallet_stats()
RETURNS VOID
LANGUAGE plpgsql VOLATILE
AS $$
BEGIN
  RAISE NOTICE 'Comparing hafbe wallet_stats_by_day with account_parameters...';

  WITH recomputed AS MATERIALIZED (
    SELECT
      ap.created::DATE AS day,
      COUNT(*)::INT    AS new_wallets
    FROM hafbe_app.account_parameters ap
    WHERE ap.created IS NOT NULL
    GROUP BY ap.created::DATE
  )
  INSERT INTO hafbe_test.differing_wallet_days (day, stored, recomputed)
  SELECT
    COALESCE(ws.day, r.day),
    ws.new_wallets,
    r.new_wallets
  FROM hafbe_app.wallet_stats_by_day ws
  FULL JOIN recomputed r ON r.day = ws.day
  WHERE ws.new_wallets IS DISTINCT FROM r.new_wallets;
END
$$;

-- =============================================================================
-- Account Operation Count Comparison
-- =============================================================================

/*
 * compare_account_ops_count: Compare hafbe_app.account_ops_count with each
 * account's newest account_op_seq_no + 1 in the context's account operations view.
 *
 * Holds at any block the context is at once massive sync is finalized: after
 * LIVE blocks and after a fork rollback, since the view and the registered
 * table follow the context's block together. Needs no hived snapshot.
 *
 * OUTPUT: Inserts differing accounts into hafbe_test.differing_ops_counts
 */
CREATE OR REPLACE FUNCTION hafbe_test.compare_account_ops_count()
RETURNS VOID
LANGUAGE plpgsql VOLATILE
AS $$
BEGIN
  RAISE NOTICE 'Comparing hafbe account_ops_count with account_operations...';

  WITH recomputed AS MATERIALIZED (
    SELECT
      av.id AS account_id,
      newest.account_op_seq_no + 1 AS ops_count
    FROM hafbe_app.accounts_view av
    CROSS JOIN LATERAL (
      SELECT aov.account_op_seq_no
      FROM hafbe_app.account_operations_view aov
      WHERE aov.account_id = av.id
      ORDER BY aov.account_op_seq_no DESC
      LIMIT 1
    ) newest
  )
  INSERT INTO hafbe_test.differing_ops_counts (account_id, stored, recomputed)
  SELECT
    COALESCE(aoc.account_id, r.account_id),
    aoc.ops_count,
    r.ops_count
  FROM hafbe_app.account_ops_count aoc
  FULL JOIN recomputed r ON r.account_id = aoc.account_id
  WHERE aoc.ops_count IS DISTINCT FROM r.ops_count;
END
$$;

-- =============================================================================
-- Debug Helpers
-- =============================================================================

/*
 * get_account_comparison: Debug helper to view expected vs computed for one account.
 *
 * Returns two rows:
 *   Row 1: Expected values from hafbe_test.expected_account_stats
 *   Row 2: Computed values from hafbe_app tables
 *
 * Usage: SELECT * FROM hafbe_test.get_account_comparison(12345);
 */
CREATE OR REPLACE FUNCTION hafbe_test.get_account_comparison(_account_id INT)
RETURNS SETOF hafbe_test.account_comparison_type
LANGUAGE plpgsql STABLE
AS $$
BEGIN
  -- Row 1: Expected values
  RETURN QUERY
  SELECT
    account_id,
    witnesses_voted_for,
    can_vote,
    mined,
    last_account_recovery,
    created,
    proxy,
    last_vote_time,
    recovery_account
  FROM hafbe_test.expected_account_stats
  WHERE account_id = _account_id;

  -- Row 2: Computed values
  RETURN QUERY
  WITH witnesses_voted AS (
    SELECT COUNT(*)::INT AS cnt
    FROM hafbe_app.current_witness_votes
    WHERE voter_id = _account_id
  ),
  params AS (
    SELECT can_vote, mined, last_account_recovery, created, recovery_account
    FROM hafbe_app.account_parameters
    WHERE account = _account_id
  ),
  proxy AS (
    SELECT proxy_id
    FROM hafbe_app.current_account_proxies
    WHERE account_id = _account_id
  )
  SELECT
    _account_id,
    COALESCE((SELECT cnt FROM witnesses_voted), 0),
    COALESCE((SELECT can_vote FROM params), TRUE),
    COALESCE((SELECT mined FROM params), TRUE),
    COALESCE((SELECT last_account_recovery FROM params), '1970-01-01T00:00:00'::TIMESTAMP),
    COALESCE((SELECT created FROM params), '1970-01-01T00:00:00'::TIMESTAMP),
    (SELECT proxy_id FROM proxy),
    NULL::TIMESTAMP,  -- last_vote_time not tracked
    COALESCE((SELECT recovery_account FROM params), '');
END
$$;

/*
 * get_witness_comparison: Debug helper to view expected vs computed for one witness.
 *
 * Returns two rows:
 *   Row 1: Expected values from hafbe_test.expected_witness_props
 *   Row 2: Computed values from hafbe_app tables
 *
 * Usage: SELECT * FROM hafbe_test.get_witness_comparison(12345);
 */
CREATE OR REPLACE FUNCTION hafbe_test.get_witness_comparison(_witness_id INT)
RETURNS SETOF hafbe_test.witness_comparison_type
LANGUAGE plpgsql STABLE
AS $$
BEGIN
  -- Row 1: Expected values
  RETURN QUERY
  SELECT
    witness_id,
    url,
    vests,
    missed_blocks,
    last_confirmed_block_num,
    signing_key,
    version,
    account_creation_fee,
    block_size,
    hbd_interest_rate,
    price_feed,
    feed_updated_at,
    created
  FROM hafbe_test.expected_witness_props
  WHERE witness_id = _witness_id;

  -- Row 2: Computed values
  RETURN QUERY
  SELECT
    _witness_id,
    cw.url,
    COALESCE((SELECT votes FROM hafbe_app.witness_votes_cache WHERE witness_id = _witness_id), 0)::BIGINT,
    cw.missed_blocks,
    cw.last_created_block_num,
    cw.signing_key,
    cw.version,
    cw.account_creation_fee,
    cw.block_size,
    cw.hbd_interest_rate,
    cw.price_feed::NUMERIC,
    cw.feed_updated_at,
    cw.created
  FROM hafbe_app.current_witnesses cw
  WHERE cw.witness_id = _witness_id;
END
$$;

RESET ROLE;
