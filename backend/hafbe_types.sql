DROP SCHEMA IF EXISTS hafbe_types CASCADE;

CREATE SCHEMA IF NOT EXISTS hafbe_types AUTHORIZATION hafbe_owner;

CREATE TYPE hafbe_types.op_types AS (
  op_type_id SMALLINT,
  operation_name TEXT,
  is_virtual BOOLEAN
);

CREATE TYPE hafbe_types.operations AS (
  trx_id TEXT,
  block INT,
  trx_in_block SMALLINT,
  op_in_trx INT,
  virtual_op BOOLEAN,
  timestamp TIMESTAMP,
  age INTERVAL,
  operation JSONB,
  operation_id BIGINT,
  acc_operation_id INT
);

CREATE TYPE hafbe_types.block AS (
  block_num INT,
  block_hash TEXT,
  timestamp TEXT,
  witness TEXT,
  signing_key TEXT
);

CREATE TYPE hafbe_types.witness_voters AS (
  account TEXT,
  votes_vests BIGINT,
  votes_hive_power BIGINT,
  account_vests BIGINT,
  account_hive_power BIGINT,
  proxied_vests BIGINT,
  proxied_hive_power BIGINT,
  timestamp TIMESTAMP
);

CREATE TYPE hafbe_types.witness_voters_daily_change AS (
  account TEXT,
  approve BOOLEAN,
  vests BIGINT,
  hive_power BIGINT,
  account_vests BIGINT,
  account_hive_power BIGINT,
  proxied_vests BIGINT,
  proxied_hive_power BIGINT,
  timestamp TIMESTAMP
);


CREATE TYPE hafbe_types.witness_setof AS (
  witness TEXT,
  rank INT,
  url TEXT,
  votes_vests BIGINT,
  votes_hive_power BIGINT,
  votes_daily_change_vests BIGINT,
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
