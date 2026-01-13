-- =============================================================================
-- HAF Block Explorer Regression Test Schema
-- =============================================================================
--
-- PURPOSE:
--   Creates the hafbe_test schema which provides infrastructure for comparing
--   HAF Block Explorer's computed values against expected values from hived.
--
-- TABLES:
--   hafbe_test.expected_account_stats   - Expected account data from hived
--   hafbe_test.expected_witness_props   - Expected witness data from hived
--   hafbe_test.differing_accounts       - Accounts with discrepancies
--   hafbe_test.differing_witnesses      - Witnesses with discrepancies
--
-- =============================================================================

SET ROLE hafbe_owner;

-- Create the test schema
DROP SCHEMA IF EXISTS hafbe_test CASCADE;
CREATE SCHEMA hafbe_test AUTHORIZATION hafbe_owner;

-- -----------------------------------------------------------------------------
-- Account comparison tables
-- -----------------------------------------------------------------------------

CREATE TABLE hafbe_test.expected_account_stats (
    account_id INT PRIMARY KEY,
    witnesses_voted_for INT,
    can_vote BOOLEAN,
    mined BOOLEAN,
    last_account_recovery TIMESTAMP,
    created TIMESTAMP,
    proxy INT,
    last_vote_time TIMESTAMP,
    recovery_account TEXT
);

CREATE TABLE hafbe_test.differing_accounts (
    account_id INT PRIMARY KEY
);

-- -----------------------------------------------------------------------------
-- Witness comparison tables
-- -----------------------------------------------------------------------------

CREATE TABLE hafbe_test.expected_witness_props (
    witness_id INT PRIMARY KEY,
    url TEXT,
    vests BIGINT,
    missed_blocks INT,
    last_confirmed_block_num INT,
    signing_key TEXT,
    version TEXT,
    account_creation_fee INT,
    block_size INT,
    hbd_interest_rate INT,
    price_feed NUMERIC,
    feed_updated_at TIMESTAMP
);

CREATE TABLE hafbe_test.differing_witnesses (
    witness_id INT PRIMARY KEY
);

RESET ROLE;
