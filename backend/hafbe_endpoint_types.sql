SET ROLE hafbe_owner;

-- Used in 
-- hafbe_endpoints.get_matching_operation_types
-- hafbe_endpoints.get_op_types
-- hafbe_endpoints.get_acc_op_types
-- hafbe_endpoints.get_block_op_types
DROP TYPE IF EXISTS hafbe_types.op_types CASCADE; -- noqa: LT01
CREATE TYPE hafbe_types.op_types AS (
    op_type_id SMALLINT,
    operation_name TEXT,
    is_virtual BOOLEAN
);

-- Used in 
-- hafbe_endpoints.get_account
DROP TYPE IF EXISTS hafbe_types.account CASCADE; -- noqa: LT01
CREATE TYPE hafbe_types.account AS (
    id INT,
    name TEXT,
    profile_image TEXT,
    json_metadata TEXT,
    posting_json_metadata TEXT,
    proxy TEXT,
    created TIMESTAMP,
    mined BOOLEAN,
    recovery_account TEXT,
    last_account_recovery TIMESTAMP,
    can_vote BOOLEAN,
    balance BIGINT,
    savings_balance BIGINT,
    hbd_balance BIGINT,
    hbd_saving_balance BIGINT,
    savings_withdraw_requests INT,
    reward_hbd_balance BIGINT,
    reward_hive_balance BIGINT,
    reward_vesting_balance BIGINT,
    reward_vesting_hive BIGINT,
    vesting_shares BIGINT,
    delegated_vesting_shares BIGINT,
    received_vesting_shares BIGINT,
    vesting_withdraw_rate BIGINT,
    to_withdraw BIGINT,
    withdrawn BIGINT,
    withdraw_routes INT,
    post_voting_power BIGINT,
    posting_rewards BIGINT,
    curation_rewards BIGINT,
    proxied_vsf_votes JSON,
    witnesses_voted_for INT,
    post_count INT,
    last_post TIMESTAMP,
    last_root_post TIMESTAMP,
    last_vote_time TIMESTAMP,
    delayed_vests BIGINT,
    vesting_balance BIGINT,
    witness_votes JSON,
    ops_count INT,
    is_witness BOOLEAN
);

-- Used in 
-- hafbe_backend.get_ops_by_account
-- hafbe_endpoints.get_ops_by_block
-- hafbe_endpoints.get_operation
DROP TYPE IF EXISTS hafbe_types.operation CASCADE; -- noqa: LT01
CREATE TYPE hafbe_types.operation AS (
    operation_id BIGINT,
    block_num INT,
    trx_in_block SMALLINT,
    trx_id TEXT,
    op_pos INT,
    op_type_id SMALLINT,
    operation JSONB,
    virtual_op BOOLEAN,
    timestamp TIMESTAMP,
    age INTERVAL,
    is_modified BOOLEAN
);

-- Used in
-- hafbe_endpoints.get_block
DROP TYPE IF EXISTS hafbe_types.block CASCADE; -- noqa: LT01
CREATE TYPE hafbe_types.block AS (
    block_num INT,
    hash bytea,
    prev bytea,
    producer_account TEXT,
    transaction_merkle_root bytea,
    extensions JSONB,
    witness_signature bytea,
    signing_key text,
    hbd_interest_rate numeric,
    total_vesting_fund_hive numeric,
    total_vesting_shares numeric,
    total_reward_fund_hive numeric,
    virtual_supply numeric,
    current_supply numeric,
    current_hbd_supply numeric,
    dhf_interval_ledger numeric,
    created_at TIMESTAMP,
    age INTERVAL
);

-- Used in
-- hafbe_endpoints.get_witness_voters
DROP TYPE IF EXISTS hafbe_types.witness_voters CASCADE; -- noqa: LT01
CREATE TYPE hafbe_types.witness_voters AS (
    voter TEXT,
    vests BIGINT,
    votes_hive_power BIGINT,
    account_vests BIGINT,
    account_hive_power BIGINT,
    proxied_vests BIGINT,
    proxied_hive_power BIGINT,
    timestamp TIMESTAMP
);

-- Used in
-- hafbe_endpoints.get_witness_votes_history
DROP TYPE IF EXISTS hafbe_types.witness_votes_history CASCADE; -- noqa: LT01
CREATE TYPE hafbe_types.witness_votes_history AS (
    voter TEXT,
    approve BOOLEAN,
    vests BIGINT,
    vests_hive_power BIGINT,
    account_vests BIGINT,
    account_hive_power BIGINT,
    proxied_vests BIGINT,
    proxied_hive_power BIGINT,
    timestamp TIMESTAMP
);

-- Used in
-- hafbe_endpoints.get_witnesses
-- hafbe_endpoints.get_witness
DROP TYPE IF EXISTS hafbe_types.witness_setof CASCADE; -- noqa: LT01
CREATE TYPE hafbe_types.witness_setof AS (
    witness TEXT,
    rank INT,
    url TEXT,
    vests BIGINT,
    votes_hive_power BIGINT,
    votes_daily_change BIGINT,
    votes_daily_change_hive_power BIGINT,
    voters_num INT,
    voters_num_daily_change INT,
    price_feed FLOAT,
    bias NUMERIC,
    feed_age INTERVAL,
    block_size INT,
    signing_key TEXT,
    version TEXT
);

-- Used in
-- hafbe_endpoints.get_transaction
DROP TYPE IF EXISTS hafbe_types.get_transaction CASCADE; -- noqa: LT01
CREATE TYPE hafbe_types.get_transaction AS (
    transaction_json JSON,
    timestamp TIMESTAMP,
    age INTERVAL
);

-- Used in
-- hafbe_endpoints.get_latest_blocks
DROP TYPE IF EXISTS hafbe_types.get_latest_blocks CASCADE; -- noqa: LT01
CREATE TYPE hafbe_types.get_latest_blocks AS (
    block_num INT,
    witness TEXT,
    ops_count JSON
);

-- Used in 
-- hafbe_backend.get_block_by_single_op
-- hafbe_backend.get_block_by_ops_group_by_block_num
-- hafbe_endpoints.get_block_by_op
DROP TYPE IF EXISTS hafbe_types.get_block_by_ops CASCADE; -- noqa: LT01
CREATE TYPE hafbe_types.get_block_by_ops AS (
    block_num INT,
    op_type_id smallint []
);

-- Used in 
-- hafbe_backend.get_comment_operations
DROP TYPE IF EXISTS hafbe_types.comment_history CASCADE; -- noqa: LT01
CREATE TYPE hafbe_types.comment_history AS (
    permlink TEXT,
    block_num INT,
    operation_id BIGINT,
    created_at TIMESTAMP,
    body JSONB,
    is_modified BOOLEAN
);


RESET ROLE;
