-- =============================================================================
-- HAF Block Explorer Regression Test Schema
-- =============================================================================
--
-- PURPOSE:
--   Creates the hafbe_test schema for comparing HAF Block Explorer's computed
--   values against expected values from hived database_api snapshots.
--
-- TABLES:
--   hafbe_test.expected_account_stats - Expected account data from hived
--   hafbe_test.expected_witness_props - Expected witness data from hived
--   hafbe_test.differing_accounts     - Accounts with discrepancies (output)
--   hafbe_test.differing_witnesses    - Witnesses with discrepancies (output)
--   hafbe_test.differing_wallet_days  - Days whose wallet count disagrees (output)
--   hafbe_test.differing_ops_counts   - Accounts whose stored op count disagrees (output)
--
-- =============================================================================

SET ROLE hafbe_owner;

DROP SCHEMA IF EXISTS hafbe_test CASCADE;
CREATE SCHEMA hafbe_test AUTHORIZATION hafbe_owner;

-- =============================================================================
-- Account Tables
-- =============================================================================

/*
 * expected_account_stats: Expected account data loaded from hived snapshot.
 *
 * Data source: hived database_api.list_accounts endpoint.
 * Fields map to hafbe_app.account_parameters and related tables.
 */
CREATE TABLE hafbe_test.expected_account_stats (
  account_id            INT       PRIMARY KEY,
  witnesses_voted_for   INT       NULL,
  can_vote              BOOLEAN   NULL,
  mined                 BOOLEAN   NULL,
  last_account_recovery TIMESTAMP NULL,
  created               TIMESTAMP NULL,
  proxy                 INT       NULL,
  last_vote_time        TIMESTAMP NULL,
  recovery_account      TEXT      NULL
);

/*
 * differing_accounts: Output table listing accounts with discrepancies.
 *
 * Populated by hafbe_test.compare_accounts().
 * Empty = all tests pass; non-empty = discrepancies found.
 */
CREATE TABLE hafbe_test.differing_accounts (
  account_id INT PRIMARY KEY
);

-- =============================================================================
-- Witness Tables
-- =============================================================================

/*
 * expected_witness_props: Expected witness data loaded from hived snapshot.
 *
 * Data source: hived database_api.list_witnesses endpoint.
 * Fields map to hafbe_app.current_witnesses and related tables.
 */
CREATE TABLE hafbe_test.expected_witness_props (
  witness_id             INT       PRIMARY KEY,
  url                    TEXT      NULL,
  vests                  BIGINT    NULL,
  missed_blocks          INT       NULL,
  last_confirmed_block_num INT     NULL,
  signing_key            TEXT      NULL,
  version                TEXT      NULL,
  account_creation_fee   INT       NULL,
  block_size             INT       NULL,
  hbd_interest_rate      INT       NULL,
  price_feed             NUMERIC   NULL,
  feed_updated_at        TIMESTAMP NULL,
  created                TIMESTAMP NULL
);

/*
 * differing_witnesses: Output table listing witnesses with discrepancies.
 *
 * Populated by hafbe_test.compare_witnesses().
 * Empty = all tests pass; non-empty = discrepancies found.
 */
CREATE TABLE hafbe_test.differing_witnesses (
  witness_id INT PRIMARY KEY
);

-- =============================================================================
-- Wallet Statistics Tables
-- =============================================================================

/*
 * differing_wallet_days: Output table listing days where
 * hafbe_app.wallet_stats_by_day disagrees with account_parameters.
 *
 * Populated by hafbe_test.compare_wallet_stats().
 * Empty = test passes; non-empty = discrepancies found.
 */
CREATE TABLE hafbe_test.differing_wallet_days (
  day         DATE PRIMARY KEY,
  stored      INT  NULL,  -- hafbe_app.wallet_stats_by_day.new_wallets (NULL = no row)
  recomputed  INT  NULL   -- accounts in account_parameters created that day (NULL = none)
);

-- =============================================================================
-- Account Operation Count Tables
-- =============================================================================

/*
 * differing_ops_counts: Output table listing accounts where
 * hafbe_app.account_ops_count disagrees with the account's newest
 * account_op_seq_no + 1.
 *
 * Populated by hafbe_test.compare_account_ops_count().
 * Empty = test passes; non-empty = discrepancies found.
 */
CREATE TABLE hafbe_test.differing_ops_counts (
  account_id  INT PRIMARY KEY,
  stored      INT NULL,  -- hafbe_app.account_ops_count.ops_count (NULL = no row)
  recomputed  INT NULL   -- newest account_op_seq_no + 1 (NULL = no operations)
);

RESET ROLE;
