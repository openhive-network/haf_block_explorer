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
  DECLARE synchronization_stages hive.application_stages;
BEGIN

  CREATE SCHEMA hafbe_app AUTHORIZATION hafbe_owner;

  IF NOT hive.app_context_exists('hafbe_app') THEN

  synchronization_stages := ARRAY[( 'MASSIVE_PROCESSING', 101, 10000 ), hive.live_stage()]::hive.application_stages;

  PERFORM hive.app_create_context(
    _name =>'hafbe_app',
    _schema => 'hafbe_app',
    _is_forking => TRUE,
    _stages => synchronization_stages
  );

  END IF;

  RAISE NOTICE 'Attempting to create an application schema tables...';

  CREATE TABLE IF NOT EXISTS hafbe_app.app_status (
    continue_processing BOOLEAN, 
    started_processing_at TIMESTAMP,
    last_reported_at TIMESTAMP,
    if_hf11 BOOLEAN
  );
  
  INSERT INTO hafbe_app.app_status (continue_processing, started_processing_at, last_reported_at, if_hf11)
  VALUES (TRUE, NULL, NULL, FALSE);

  CREATE TABLE IF NOT EXISTS hafbe_app.version(
  git_hash TEXT
  );

  INSERT INTO hafbe_app.version VALUES('unspecified (generate and apply set_version_in_sql.pgsql)');

------------------------------------------

  CREATE TABLE IF NOT EXISTS hafbe_app.block_operations
  (
    block_num INT NOT NULL, 
    op_type_id INT NOT NULL,
    op_count INT NOT NULL
  );

  PERFORM hive.app_register_table( 'hafbe_app', 'block_operations', 'hafbe_app' );

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
  );

  PERFORM hive.app_register_table( 'hafbe_app', 'account_parameters', 'hafbe_app' );

------------------------------------------

-- Updated by hafbe_app.process_block_range_data_a
  CREATE TABLE IF NOT EXISTS hafbe_app.witness_votes_history (
    witness_id INT NOT NULL,
    voter_id INT NOT NULL,
    approve BOOLEAN NOT NULL,
    timestamp TIMESTAMP NOT NULL
  );
  PERFORM hive.app_register_table( 'hafbe_app', 'witness_votes_history', 'hafbe_app' );

  CREATE TABLE IF NOT EXISTS hafbe_app.current_witness_votes (
    voter_id INT NOT NULL,
    witness_id INT NOT NULL,
    timestamp TIMESTAMP NOT NULL,

    CONSTRAINT pk_current_witness_votes PRIMARY KEY (voter_id, witness_id)
  );
  PERFORM hive.app_register_table( 'hafbe_app', 'current_witness_votes', 'hafbe_app' );

  CREATE TABLE IF NOT EXISTS hafbe_app.account_proxies_history (
    account_id INT NOT NULL,
    proxy_id INT NOT NULL,
    proxy BOOLEAN NOT NULL,
    timestamp TIMESTAMP NOT NULL
  );
  PERFORM hive.app_register_table( 'hafbe_app', 'account_proxies_history', 'hafbe_app' );

  CREATE TABLE IF NOT EXISTS hafbe_app.current_account_proxies (
    account_id INT NOT NULL,
    proxy_id INT NOT NULL,

    CONSTRAINT pk_current_account_proxies PRIMARY KEY (account_id)
  );
  PERFORM hive.app_register_table( 'hafbe_app', 'current_account_proxies', 'hafbe_app' );

------------------------------------------

CREATE TABLE IF NOT EXISTS hafbe_app.transaction_stats_by_month
(
  trx_count INT NOT NULL,
  avg_trx INT NOT NULL,
  min_trx INT NOT NULL,
  max_trx INT NOT NULL,
  last_block_num INT NOT NULL,
  updated_at TIMESTAMP NOT NULL,

  CONSTRAINT pk_transaction_stats_by_month PRIMARY KEY (updated_at)
);
PERFORM hive.app_register_table( 'hafbe_app', 'transaction_stats_by_month', 'hafbe_app' );

CREATE TABLE IF NOT EXISTS hafbe_app.transaction_stats_by_day
(
  trx_count INT NOT NULL,
  avg_trx INT NOT NULL,
  min_trx INT NOT NULL,
  max_trx INT NOT NULL,
  last_block_num INT NOT NULL,
  updated_at TIMESTAMP NOT NULL,

  CONSTRAINT pk_transaction_stats_by_day PRIMARY KEY (updated_at)
);
PERFORM hive.app_register_table( 'hafbe_app', 'transaction_stats_by_day', 'hafbe_app' );

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
    last_created_block_num INT,
    account_creation_fee INT,
    missed_blocks INT DEFAULT 0,

    CONSTRAINT pk_current_witnesses PRIMARY KEY (witness_id)
  );
  PERFORM hive.app_register_table( 'hafbe_app', 'current_witnesses', 'hafbe_app' );

  CREATE TABLE IF NOT EXISTS hafbe_app.balance_impacting_op_ids (
    op_type_ids_arr SMALLINT[] NOT NULL
  );

------------------------------------------

-- Used in witness endpoints
-- Updated by hafbe_app.update_witnesses_cache
  INSERT INTO hafbe_app.balance_impacting_op_ids (op_type_ids_arr)
  SELECT array_agg(hot.id)
  FROM hafd.operation_types hot
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
  );
  PERFORM hive.app_register_table( 'hafbe_app', 'sync_time_logs', 'hafbe_app' );

------------------------------------------

EXCEPTION WHEN duplicate_schema THEN RAISE NOTICE '%, skipping', SQLERRM USING ERRCODE = SQLSTATE;

END
$$;

RESET ROLE;
