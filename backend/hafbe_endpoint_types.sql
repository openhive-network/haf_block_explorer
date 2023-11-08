SET ROLE hafbe_owner;

DROP TYPE IF EXISTS hafbe_types.op_types CASCADE;
CREATE TYPE hafbe_types.op_types AS (
  op_type_id SMALLINT,
  operation_name TEXT,
  is_virtual BOOLEAN
);

DROP TYPE IF EXISTS hafbe_types.account CASCADE;
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

DROP TYPE IF EXISTS hafbe_types.operation CASCADE;
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

DROP TYPE IF EXISTS hafbe_types.block CASCADE;
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

DROP TYPE IF EXISTS hafbe_types.witness_voters CASCADE;
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

DROP TYPE IF EXISTS hafbe_types.witness_votes_history CASCADE;
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

DROP TYPE IF EXISTS hafbe_types.witness_setof CASCADE;
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

DROP TYPE IF EXISTS hafbe_types.get_transaction CASCADE;
CREATE TYPE hafbe_types.get_transaction AS (
  transaction_json JSON,
  timestamp TIMESTAMP,
  age INTERVAL
);

DROP TYPE IF EXISTS hafbe_types.get_latest_blocks CASCADE;
CREATE TYPE hafbe_types.get_latest_blocks AS (
  block_num INT,
  witness TEXT,
  ops_count JSON
);

DROP TYPE IF EXISTS hafbe_types.get_block_by_ops_group_by_op_type_id CASCADE;
CREATE TYPE hafbe_types.get_block_by_ops_group_by_op_type_id AS (
  op_type_id smallint,
  block_num INT[]
);

DROP TYPE IF EXISTS hafbe_types.get_block_by_ops_group_by_block_num CASCADE;
CREATE TYPE hafbe_types.get_block_by_ops_group_by_block_num AS (
  block_num INT,
  op_type_id smallint[]
);

RESET ROLE;
