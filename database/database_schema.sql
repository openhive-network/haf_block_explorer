CREATE SCHEMA IF NOT EXISTS hafbe_app AUTHORIZATION hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_app.define_schema()
RETURNS VOID
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RAISE NOTICE 'Attempting to create an application schema tables...';

  CREATE TABLE IF NOT EXISTS hafbe_app.app_status (
    continue_processing BOOLEAN,
    last_processed_block INT,
    started_processing_at TIMESTAMP,
    finished_processing_at TIMESTAMP,
    last_reported_at TIMESTAMP,
    last_reported_block INT
  );
  
  INSERT INTO hafbe_app.app_status (continue_processing, last_processed_block, started_processing_at, finished_processing_at, last_reported_at, last_reported_block)
  VALUES (TRUE, 0, NULL, NULL, to_timestamp(0), 0);

  -- witnesses

  CREATE TABLE IF NOT EXISTS hafbe_app.current_witnesses (
    witness_id INT NOT NULL,
    url TEXT,
    price_feed FLOAT,
    bias NUMERIC,
    feed_updated_at TIMESTAMP,
    block_size INT,
    signing_key TEXT,
    version TEXT,

    CONSTRAINT pk_current_witnesses PRIMARY KEY (witness_id)
  ) INHERITS (hive.hafbe_app);

  -- witness votes

  CREATE TABLE IF NOT EXISTS hafbe_app.witness_votes_history (
    id SERIAL PRIMARY KEY,
    witness_id INT NOT NULL,
    voter_id INT NOT NULL,
    approve BOOLEAN NOT NULL,
    timestamp TIMESTAMP NOT NULL
  ) INHERITS (hive.hafbe_app);

  CREATE TABLE IF NOT EXISTS hafbe_app.current_witness_votes (
    witness_id INT NOT NULL,
    voter_id INT NOT NULL,
    timestamp TIMESTAMP NOT NULL,

    CONSTRAINT pk_current_witness_votes PRIMARY KEY (witness_id, voter_id)
  ) INHERITS (hive.hafbe_app);


  -- witness proxies

  CREATE TABLE IF NOT EXISTS hafbe_app.account_proxies_history (
    id SERIAL PRIMARY KEY,
    account_id INT NOT NULL,
    proxy_id INT NOT NULL,
    timestamp TIMESTAMP NOT NULL
  ) INHERITS (hive.hafbe_app);

  CREATE TABLE IF NOT EXISTS hafbe_app.current_account_proxies (
    account_id INT NOT NULL,
    proxy_id INT NOT NULL,

    CONSTRAINT pk_current_account_proxies PRIMARY KEY (account_id)
  ) INHERITS (hive.hafbe_app);

  CREATE TABLE IF NOT EXISTS hafbe_app.hived_account_cache (
    account TEXT NOT NULL,
    data JSON NOT NULL,
    last_updated_at TIMESTAMP,

    CONSTRAINT pk_hived_account_cache PRIMARY KEY (account)
  );

  CREATE TABLE IF NOT EXISTS hafbe_app.hived_account_resource_credits_cache (
    account TEXT NOT NULL,
    data JSON NOT NULL,
    last_updated_at TIMESTAMP,

    CONSTRAINT pk_hived_account_resource_credits_cache PRIMARY KEY (account)
  );

  CREATE TABLE IF NOT EXISTS hafbe_app.balance_impacting_op_ids (
    op_type_ids_arr SMALLINT[] NOT NULL
  );

  INSERT INTO hafbe_app.balance_impacting_op_ids (op_type_ids_arr)
  SELECT array_agg(hot.id)
  FROM hive.operation_types hot
  JOIN (
    SELECT get_balance_impacting_operations AS name
    FROM hive.get_balance_impacting_operations()
  ) bio ON bio.name = hot.name::TEXT;

  CREATE TABLE IF NOT EXISTS hafbe_app.account_vests (
    account_id INT NOT NULL,
    vests BIGINT NOT NULL,

    CONSTRAINT pk_account_vests PRIMARY KEY (account_id)
  ) INHERITS (hive.hafbe_app);

  CREATE TABLE IF NOT EXISTS hafbe_app.witnesses_cache_config (
    update_interval INTERVAL,
    last_updated_at TIMESTAMP
  );

  INSERT INTO hafbe_app.witnesses_cache_config (update_interval, last_updated_at)
  VALUES ('30 minutes', to_timestamp(0));

  CREATE TABLE IF NOT EXISTS hafbe_app.witness_voters_stats_cache (
    witness_id INT NOT NULL,
    voter_id INT NOT NULL,
    vests NUMERIC NOT NULL,
    account_vests NUMERIC NOT NULL,
    proxied_vests NUMERIC NOT NULL,
    timestamp TIMESTAMP NOT NULL,

    CONSTRAINT pk_witness_voters_stats_cache PRIMARY KEY (witness_id, voter_id)
  );

  CREATE TABLE IF NOT EXISTS hafbe_app.witness_votes_cache (
    witness_id INT NOT NULL,
    rank INT NOT NULL,
    votes NUMERIC NOT NULL,
    voters_num INT NOT NULL,

    CONSTRAINT pk_witness_votes_cache PRIMARY KEY (witness_id)
  );

  CREATE TABLE IF NOT EXISTS hafbe_app.witness_voters_stats_change_cache (
    witness_id INT NOT NULL,
    voter_id INT NOT NULL,
    vests NUMERIC NOT NULL,
    account_vests NUMERIC NOT NULL,
    proxied_vests NUMERIC NOT NULL,
    approve BOOLEAN NOT NULL,
    timestamp TIMESTAMP NOT NULL
  );

  CREATE TABLE IF NOT EXISTS hafbe_app.witness_votes_change_cache (
    witness_id INT NOT NULL,
    votes_daily_change BIGINT NOT NULL,
    voters_num_daily_change INT NOT NULL,

    CONSTRAINT pk_witness_votes_change_cache PRIMARY KEY (witness_id)
  );
END
$$
;
