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
  operations JSON,
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

CREATE TYPE hafbe_types.witness_voters_in_vests AS (
  account TEXT,
  vests NUMERIC,
  account_vests NUMERIC,
  proxied_vests NUMERIC,
  timestamp TIMESTAMP
);

CREATE TYPE hafbe_types.witness_voters_in_hp AS (
  account TEXT,
  hive_power FLOAT,
  account_hive_power FLOAT,
  proxied_hive_power FLOAT,
  timestamp TIMESTAMP
);

CREATE TYPE hafbe_types.witness_voters_daily_change_in_vests AS (
  account TEXT,
  approve BOOLEAN,
  vests BIGINT,
  account_vests BIGINT,
  proxied_vests BIGINT,
  timestamp TIMESTAMP
);

CREATE TYPE hafbe_types.witness_voters_daily_change_in_hp AS (
  account TEXT,
  approve BOOLEAN,
  hive_power FLOAT,
  account_hive_power FLOAT,
  proxied_hive_power FLOAT,
  timestamp TIMESTAMP
);

CREATE TYPE hafbe_types.witnesses_in_vests AS (
  witness TEXT,
  rank INT,
  url TEXT,
  votes NUMERIC,
  votes_daily_change BIGINT,
  voters_num INT,
  voters_num_daily_change INT,
  price_feed FLOAT,
  bias NUMERIC,
  feed_age INTERVAL,
  block_size INT,
  signing_key TEXT,
  version TEXT
);

CREATE TYPE hafbe_types.witnesses_in_hp AS (
  witness TEXT,
  rank INT,
  url TEXT,
  votes FLOAT,
  votes_daily_change FLOAT,
  voters_num INT,
  voters_num_daily_change INT,
  price_feed FLOAT,
  bias NUMERIC,
  feed_age INTERVAL,
  block_size INT,
  signing_key TEXT,
  version TEXT
);