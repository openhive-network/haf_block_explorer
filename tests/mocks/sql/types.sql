-- =============================================================================
-- HAFBE Mock Data Type Definitions
-- =============================================================================
-- Composite types used by json_populate_recordset to parse fixture JSON.
-- Mirrors the btracker mock framework (see submodules/btracker/tests/mocks/sql).
-- =============================================================================

SET ROLE hafbe_owner;

DROP TYPE IF EXISTS hafbe_backend.mock_operation_type CASCADE;
CREATE TYPE hafbe_backend.mock_operation_type AS (
    block_num    INT,
    op_name      TEXT,    -- e.g. 'hive::protocol::create_proposal_operation'
    op_pos       INT,
    trx_in_block INT,
    body         JSON
);

DROP TYPE IF EXISTS hafbe_backend.mock_block_type CASCADE;
CREATE TYPE hafbe_backend.mock_block_type AS (
    block_num               INT,
    hash                    TEXT,
    prev                    TEXT,
    producer_account        TEXT,
    transaction_merkle_root TEXT,
    extensions              JSONB,
    witness_signature       TEXT,
    signing_key             TEXT,
    hbd_interest_rate       BIGINT,
    total_vesting_fund_hive TEXT,
    total_vesting_shares    TEXT,
    total_reward_fund_hive  TEXT,
    virtual_supply          TEXT,
    current_supply          TEXT,
    current_hbd_supply      TEXT,
    dhf_interval_ledger     BIGINT,
    created_at              TIMESTAMP
);

RESET ROLE;
