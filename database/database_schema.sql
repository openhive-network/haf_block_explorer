SET ROLE hafbe_owner;

--TIME OF HAFBE SYNC FOR 15m BLOCKS

--0 pre changes around 38 minutes
--1st pass 55.67 minutes
--2nd pass after optimalization 53.45 minutes
--3rd pass without rewards, with optimalizations 33.65 minutes
--4th pass without hive_vesting_balance 44.95 minutes

--withdraws 86.44m
--2nd pass after optimalizations 61m
--3rd pass more opt 59.80m
--4rd pass changing to CTE only on rewards 59.63m
--5rd pass changing to CTE where its possible 59.67m

--changing account string into account_id 49.24m
--withdraws had an issue, it didn't update on the end of a withdraw, fixing it added +-4 minutes to sync. 54m

--extendend rewards (posting, curation rewards) 61.56m

--posts and votes 69.61m

DO $$
BEGIN

  CREATE SCHEMA hafbe_app AUTHORIZATION hafbe_owner;

  IF NOT hive.app_context_exists('hafbe_app') THEN 

  PERFORM hive.app_create_context('hafbe_app',
    TRUE, -- _if_forking
    FALSE -- _is_attached
    );

  END IF;

  RAISE NOTICE 'Attempting to create an application schema tables...';

  CREATE TABLE IF NOT EXISTS hafbe_app.app_status (
    continue_processing BOOLEAN,
    started_processing_at TIMESTAMP,
    finished_processing_at TIMESTAMP,
    last_reported_at TIMESTAMP,
    last_reported_block INT,
    if_hf11 BOOLEAN
  );
  
  INSERT INTO hafbe_app.app_status (continue_processing, started_processing_at, finished_processing_at, last_reported_at, last_reported_block, if_hf11)
  VALUES (TRUE, NULL, NULL, to_timestamp(0), 0, FALSE);

  CREATE TABLE IF NOT EXISTS hafbe_app.version(
  schema_hash TEXT,
  runtime_hash TEXT
  );

------------------------------------------

  CREATE TABLE IF NOT EXISTS hafbe_app.account_parameters
  (
    account INT NOT NULL, 
    can_vote BOOLEAN DEFAULT TRUE,
    mined BOOLEAN DEFAULT TRUE,
    recovery_account TEXT DEFAULT '',
    last_account_recovery TIMESTAMP DEFAULT '1970-01-01T00:00:00',
    created TIMESTAMP DEFAULT '1970-01-01T00:00:00',

    CONSTRAINT pk_account_parameters PRIMARY KEY (account)
  ) INHERITS (hive.hafbe_app);

------------------------------------------

-- Updated by hafbe_app.process_block_range_data_a
  CREATE TABLE IF NOT EXISTS hafbe_app.witness_votes_history (
    witness_id INT NOT NULL,
    voter_id INT NOT NULL,
    approve BOOLEAN NOT NULL,
    timestamp TIMESTAMP NOT NULL
  ) INHERITS (hive.hafbe_app);

  CREATE TABLE IF NOT EXISTS hafbe_app.current_witness_votes (
    voter_id INT NOT NULL,
    witness_id INT NOT NULL,
    timestamp TIMESTAMP NOT NULL,

    CONSTRAINT pk_current_witness_votes PRIMARY KEY (voter_id, witness_id)
  ) INHERITS (hive.hafbe_app);

  CREATE TABLE IF NOT EXISTS hafbe_app.account_proxies_history (
    account_id INT NOT NULL,
    proxy_id INT NOT NULL,
    proxy BOOLEAN NOT NULL,
    timestamp TIMESTAMP NOT NULL
  ) INHERITS (hive.hafbe_app);

  CREATE TABLE IF NOT EXISTS hafbe_app.current_account_proxies (
    account_id INT NOT NULL,
    proxy_id INT NOT NULL,

    CONSTRAINT pk_current_account_proxies PRIMARY KEY (account_id)
  ) INHERITS (hive.hafbe_app);

------------------------------------------

-- Updated by hafbe_app.process_block_range_data_b
  CREATE TABLE IF NOT EXISTS hafbe_app.current_witnesses (
    witness_id INT NOT NULL,
    url TEXT,
    price_feed FLOAT,
    bias NUMERIC,
    feed_updated_at TIMESTAMP,
    block_size INT,
    signing_key TEXT,
    version TEXT, 
    hbd_interest_rate INT,

    CONSTRAINT pk_current_witnesses PRIMARY KEY (witness_id)
  ) INHERITS (hive.hafbe_app);

  CREATE TABLE IF NOT EXISTS hafbe_app.balance_impacting_op_ids (
    op_type_ids_arr SMALLINT[] NOT NULL
  );

------------------------------------------

-- Used in witness endpoints
-- Updated by hafbe_app.update_witnesses_cache
  INSERT INTO hafbe_app.balance_impacting_op_ids (op_type_ids_arr)
  SELECT array_agg(hot.id)
  FROM hive.operation_types hot
  JOIN (
    SELECT get_balance_impacting_operations AS name
    FROM hive.get_balance_impacting_operations()
  ) bio ON bio.name = hot.name::TEXT;

  CREATE TABLE IF NOT EXISTS hafbe_app.witnesses_cache_config (
    update_interval INTERVAL,
    last_updated_at TIMESTAMP
  );

  INSERT INTO hafbe_app.witnesses_cache_config (update_interval, last_updated_at)
  VALUES ('10 minutes', to_timestamp(0));

  CREATE TABLE IF NOT EXISTS hafbe_app.witness_voters_stats_cache (
    witness_id INT NOT NULL,
    voter_id INT NOT NULL,
    vests BIGINT NOT NULL,
    account_vests BIGINT NOT NULL,
    proxied_vests BIGINT NOT NULL,
    timestamp TIMESTAMP NOT NULL,

    CONSTRAINT pk_witness_voters_stats_cache PRIMARY KEY (witness_id, voter_id)
  );

  CREATE TABLE IF NOT EXISTS hafbe_app.witness_votes_cache (
    witness_id INT NOT NULL,
    rank INT NOT NULL,
    votes BIGINT NOT NULL,
    voters_num INT NOT NULL,

    CONSTRAINT pk_witness_votes_cache PRIMARY KEY (witness_id)
  );

  CREATE TABLE IF NOT EXISTS hafbe_app.witness_votes_history_cache (
    witness_id INT NOT NULL,
    voter_id INT NOT NULL,
    approve BOOLEAN NOT NULL,
    account_vests BIGINT NOT NULL,
    proxied_vests BIGINT NOT NULL,
    timestamp TIMESTAMP NOT NULL
  );

  CREATE TABLE IF NOT EXISTS hafbe_app.witness_votes_change_cache (
    witness_id INT NOT NULL,
    votes_daily_change BIGINT NOT NULL,
    voters_num_daily_change INT NOT NULL,

    CONSTRAINT pk_witness_votes_change_cache PRIMARY KEY (witness_id)
  );

  CREATE TABLE IF NOT EXISTS hafbe_app.sync_time_logs (
    block_num INT NOT NULL,
    time_json JSONB NOT NULL,

    CONSTRAINT pk_massive_sync_time_logs PRIMARY KEY (block_num)
  ) INHERITS (hive.hafbe_app);

------------------------------------------

GRANT ALL ON SCHEMA btracker_app TO hafbe_owner;

GRANT ALL ON SCHEMA btracker_endpoints TO hafbe_owner;

EXCEPTION WHEN duplicate_schema THEN RAISE NOTICE '%, skipping', SQLERRM USING ERRCODE = SQLSTATE;

END
$$;

RESET ROLE;
