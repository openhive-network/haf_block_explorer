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
  timestamp TEXT,
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

CREATE TYPE hafbe_types.witness_voters_by_name AS (
  voter_id INT,
  voter TEXT
);

CREATE TYPE hafbe_types.witness_voters_by_vests AS (
  voter_id INT,
  vests NUMERIC,
  account_vests NUMERIC,
  proxied_vests NUMERIC,
  timestamp TIMESTAMP
);

CREATE TYPE hafbe_types.witness_voters AS (
  account TEXT,
  vests NUMERIC,
  account_vests NUMERIC,
  proxied_vests NUMERIC,
  timestamp TIMESTAMP
);

CREATE TYPE hafbe_types.witness_voters_daily_change_by_name AS (
  witness_id INT,
  voter_id INT,  
  voter TEXT,
  approve BOOLEAN
);

CREATE TYPE hafbe_types.witness_voters_daily_change_by_vests AS (
  voter_id INT,
  vests BIGINT,
  account_vests BIGINT,
  proxied_vests BIGINT,
  timestamp TIMESTAMP,
  approve BOOLEAN
);

CREATE TYPE hafbe_types.witness_voters_daily_change AS (
  account TEXT,
  approve BOOLEAN,
  vests BIGINT,
  account_vests BIGINT,
  proxied_vests BIGINT,
  timestamp TIMESTAMP
);

CREATE TYPE hafbe_types.witnesses_by_name AS (
  witness_id INT,
  witness TEXT,
  url TEXT,
  price_feed FLOAT,
  bias NUMERIC,
  feed_age INTERVAL,
  block_size INT,
  signing_key TEXT,
  version TEXT
);

CREATE TYPE hafbe_types.witnesses_by_votes AS (
  witness_id INT,
  rank INT,
  votes NUMERIC,
  voters_num INT
);

CREATE TYPE hafbe_types.witnesses_by_votes_change AS (
  witness_id INT,
  votes_daily_change BIGINT,
  voters_num_daily_change INT
);

CREATE TYPE hafbe_types.witnesses_by_prop AS (
  witness_id INT,
  url TEXT,
  price_feed FLOAT,
  bias NUMERIC,
  feed_age INTERVAL,
  block_size INT,
  signing_key TEXT,
  version TEXT
);

CREATE TYPE hafbe_types.witnesses AS (
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