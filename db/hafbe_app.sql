-- noqa: disable=CP03

SET ROLE hafbe_owner;

-- =============================================================================
-- HAFBE_APP - HAF Block Explorer Application Schema
-- =============================================================================
-- This file contains:
--   1. Schema creation and HAF context registration
--   2. Table definitions (core + cache tables)
--   3. Helper functions for processing control
--   4. Block processing orchestration
--   5. Main entry point
-- =============================================================================

-- =============================================================================
-- SECTION 1: SCHEMA CREATION AND TABLES
-- =============================================================================

DO $$
  DECLARE synchronization_stages hive.application_stages;
BEGIN

  CREATE SCHEMA hafbe_app AUTHORIZATION hafbe_owner;

  IF NOT hive.app_context_exists('hafbe_app') THEN

  synchronization_stages := ARRAY[hive.stage( 'MASSIVE_PROCESSING', 101, 10000, '20 seconds' ), hive.live_stage()]::hive.application_stages;

  PERFORM hive.app_create_context(
     _name =>'hafbe_app',
     _schema => 'hafbe_app',
     _is_forking => current_setting('custom.is_forking')::BOOLEAN,
     _stages => synchronization_stages
  );

  END IF;

  RAISE NOTICE 'Attempting to create an application schema tables...';

  -- Application status table
  CREATE TABLE IF NOT EXISTS hafbe_app.app_status (
    continue_processing BOOLEAN,
    started_processing_at TIMESTAMP,
    last_reported_at TIMESTAMP,
    if_hf11 BOOLEAN
  );

  INSERT INTO hafbe_app.app_status (continue_processing, started_processing_at, last_reported_at, if_hf11)
  VALUES (TRUE, NULL, NULL, FALSE);

  -- Version tracking table
  CREATE TABLE IF NOT EXISTS hafbe_app.version(
  git_hash TEXT
  );

  INSERT INTO hafbe_app.version VALUES('unspecified (generate and apply set_version_in_sql.pgsql)');

------------------------------------------
-- Block operations aggregation

  CREATE TABLE IF NOT EXISTS hafbe_app.block_operations
  (
    block_num INT NOT NULL,
    op_type_id INT NOT NULL,
    op_count INT NOT NULL
  );

  PERFORM hive.app_register_table( 'hafbe_app', 'block_operations', 'hafbe_app' );

------------------------------------------
-- Account parameters

  CREATE TABLE IF NOT EXISTS hafbe_app.account_parameters
  (
    account INT NOT NULL,
    can_vote BOOLEAN DEFAULT TRUE,
    mined BOOLEAN DEFAULT TRUE,
    recovery_account TEXT DEFAULT '',
    last_account_recovery TIMESTAMP DEFAULT '1970-01-01T00:00:00',
    created TIMESTAMP DEFAULT '1970-01-01T00:00:00',
    pending_claimed_accounts INT DEFAULT 0,

    CONSTRAINT pk_account_parameters PRIMARY KEY (account)
  );

  PERFORM hive.app_register_table( 'hafbe_app', 'account_parameters', 'hafbe_app' );

------------------------------------------
-- Witness votes and proxy tables

  CREATE TABLE IF NOT EXISTS hafbe_app.witness_votes_history (
    witness_id INT NOT NULL,
    voter_id INT NOT NULL,
    approve BOOLEAN NOT NULL,
    source_op BIGINT NOT NULL

  );
  PERFORM hive.app_register_table( 'hafbe_app', 'witness_votes_history', 'hafbe_app' );

  CREATE TABLE IF NOT EXISTS hafbe_app.current_witness_votes (
    voter_id INT NOT NULL,
    witness_id INT NOT NULL,
    source_op BIGINT NOT NULL,

    CONSTRAINT pk_current_witness_votes PRIMARY KEY (voter_id, witness_id)
  );
  PERFORM hive.app_register_table( 'hafbe_app', 'current_witness_votes', 'hafbe_app' );

  CREATE TABLE IF NOT EXISTS hafbe_app.account_proxies_history (
    account_id INT NOT NULL,
    proxy_id INT NOT NULL,
    proxy BOOLEAN NOT NULL,
    source_op BIGINT NOT NULL

  );
  PERFORM hive.app_register_table( 'hafbe_app', 'account_proxies_history', 'hafbe_app' );

  CREATE TABLE IF NOT EXISTS hafbe_app.current_account_proxies (
    account_id INT NOT NULL,
    proxy_id INT NOT NULL,
    source_op BIGINT NOT NULL,

    CONSTRAINT pk_current_account_proxies PRIMARY KEY (account_id)
  );
  PERFORM hive.app_register_table( 'hafbe_app', 'current_account_proxies', 'hafbe_app' );

------------------------------------------
-- Transaction statistics tables

  CREATE TABLE IF NOT EXISTS hafbe_app.transaction_stats_by_month
  (
    trx_count INT NOT NULL,
    count_blocks INT NOT NULL,
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
    count_blocks INT NOT NULL,
    min_trx INT NOT NULL,
    max_trx INT NOT NULL,
    last_block_num INT NOT NULL,
    updated_at TIMESTAMP NOT NULL,

    CONSTRAINT pk_transaction_stats_by_day PRIMARY KEY (updated_at)
  );
  PERFORM hive.app_register_table( 'hafbe_app', 'transaction_stats_by_day', 'hafbe_app' );

------------------------------------------
-- Witness statistics table

  CREATE TABLE IF NOT EXISTS hafbe_app.current_witnesses
  (
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

------------------------------------------
-- Sync timing logs

  CREATE TABLE IF NOT EXISTS hafbe_app.sync_time_logs (
    block_num INT NOT NULL,
    time_json JSONB NOT NULL,

    CONSTRAINT pk_massive_sync_time_logs PRIMARY KEY (block_num)
  );
  PERFORM hive.app_register_table( 'hafbe_app', 'sync_time_logs', 'hafbe_app' );

------------------------------------------
-- Cache tables (updated only during live sync)
-- These tables store cached witness vest statistics,
-- which are updated exclusively during live synchronization at each block.

  CREATE TABLE IF NOT EXISTS hafbe_app.account_vest_stats_cache (
    account_id INT NOT NULL,
    vests BIGINT NOT NULL,
    account_vests BIGINT NOT NULL,
    proxied_vests BIGINT NOT NULL,

    CONSTRAINT pk_account_vest_stats_cache PRIMARY KEY (account_id)
  );

  CREATE TABLE IF NOT EXISTS hafbe_app.witness_votes_cache (
    witness_id INT NOT NULL,
    votes BIGINT NOT NULL,
    voters_num INT NOT NULL,

    CONSTRAINT pk_witness_votes_cache PRIMARY KEY (witness_id)
  );

  CREATE TABLE IF NOT EXISTS hafbe_app.witness_rank_cache (
    witness_id INT NOT NULL,
    rank INT NOT NULL,

    CONSTRAINT pk_witness_rank_cache PRIMARY KEY (witness_id)
  );

  CREATE TABLE IF NOT EXISTS hafbe_app.witness_votes_change_cache (
    witness_id INT NOT NULL,
    votes_daily_change BIGINT NOT NULL,
    voters_num_daily_change INT NOT NULL,

    CONSTRAINT pk_witness_votes_change_cache PRIMARY KEY (witness_id)
  );

------------------------------------------

EXCEPTION WHEN duplicate_schema THEN RAISE NOTICE '%, skipping', SQLERRM USING ERRCODE = SQLSTATE;

END
$$;

-- =============================================================================
-- SECTION 2: HELPER FUNCTIONS FOR PROCESSING CONTROL
-- =============================================================================

--- Helper function telling application main-loop to continue execution.
CREATE OR REPLACE FUNCTION hafbe_app.continueProcessing()
RETURNS BOOLEAN
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN continue_processing FROM hafbe_app.app_status LIMIT 1;
END
$$;

CREATE OR REPLACE FUNCTION hafbe_app.allowProcessing()
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
  UPDATE hafbe_app.app_status SET continue_processing = True;
END
$$;

--- Helper function to be called from separate transaction (must be committed)
--- to safely stop execution of the application.
CREATE OR REPLACE FUNCTION hafbe_app.stopProcessing()
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
  UPDATE hafbe_app.app_status SET continue_processing = False;
END
$$;

-- =============================================================================
-- SECTION 3: INDEX CHECK FUNCTIONS
-- =============================================================================

CREATE OR REPLACE FUNCTION hafbe_app.isIndexesCreated()
RETURNS BOOLEAN
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN EXISTS(
      SELECT true FROM pg_index WHERE indexrelid =
      (
        SELECT oid FROM pg_class WHERE relname = 'witness_votes_history_witness_voter'
      )
    );
END
$$;

CREATE OR REPLACE FUNCTION hafbe_app.isCommentSearchIndexesCreated()
RETURNS BOOLEAN
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN EXISTS(
      SELECT true FROM pg_index WHERE indexrelid =
      (
        SELECT oid FROM pg_class WHERE relname = 'hive_operations_comment_search_permlink_author'
      )
    );
END
$$;

CREATE OR REPLACE FUNCTION hafbe_app.isBlockSearchIndexesCreated()
RETURNS BOOLEAN
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN EXISTS(
      SELECT true FROM pg_index WHERE indexrelid =
      (
        SELECT oid FROM pg_class WHERE relname = 'hive_operations_vote_author_permlink'
      )
    );
END
$$;

-- =============================================================================
-- SECTION 4: CONTEXT AND BLOCK PROCESSING
-- =============================================================================

CREATE OR REPLACE PROCEDURE hafbe_app.create_context_if_not_exists(_appContext VARCHAR)
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  IF NOT hive.app_context_exists(_appContext) THEN
    RAISE NOTICE 'Attempting to create a HAF application context...';
    PERFORM hive.app_create_context(
      _name => _appContext,
      _schema => _appContext,
      _is_forking => TRUE,
      _is_attached => FALSE
    );
    COMMIT;
  END IF;
END
$$;

CREATE OR REPLACE FUNCTION hafbe_app.process_blocks(
    _context_name hive.context_name,
    _block_range hive.blocks_range,
    _logs BOOLEAN = true
)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
  IF hive.get_current_stage_name(_context_name) = 'MASSIVE_PROCESSING' THEN
    CALL hafbe_app.massive_processing(_block_range.first_block, _block_range.last_block, _logs);
    PERFORM hive.app_request_table_vacuum('hafbe_app', 'current_witness_votes', interval '30 minutes');
    PERFORM hive.app_request_table_vacuum('hafbe_app', 'current_witnesses', interval '30 minutes');
    PERFORM hive.app_request_table_vacuum('hafbe_app', 'current_account_proxies', interval '30 minutes');

    RETURN;
  END IF;
  IF NOT hafbe_app.isIndexesCreated() THEN
    PERFORM hafbe_indexes.create_hafbe_indexes();
  END IF;
  CALL hafbe_app.single_processing(_block_range.first_block, _logs);
  -- cache tables needs to be vacuumed, due to change from `TRUNCATE TABLE` to `DELETE FROM` in block processing
  PERFORM hive.app_request_table_vacuum('hafbe_app', 'account_vest_stats_cache',   interval '10 minutes');
  PERFORM hive.app_request_table_vacuum('hafbe_app', 'witness_votes_cache',        interval '10 minutes');
  PERFORM hive.app_request_table_vacuum('hafbe_app', 'witness_rank_cache',         interval '10 minutes');
  PERFORM hive.app_request_table_vacuum('hafbe_app', 'witness_votes_change_cache', interval '10 minutes');
END
$$;

CREATE OR REPLACE PROCEDURE hafbe_app.massive_processing(
    IN _from INT,
    IN _to INT,
    IN _logs BOOLEAN
)
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __start_ts timestamptz;
  __end_ts   timestamptz;
BEGIN
  PERFORM set_config('synchronous_commit', 'OFF', false);

  IF _logs THEN
    RAISE NOTICE 'Hafbe is attempting to process a block range: <%, %>', _from, _to;
    __start_ts := clock_timestamp();
  END IF;

  PERFORM hafbe_app.process_account_stats(_from, _to);
  PERFORM hafbe_app.process_block_operations(_from, _to);
  PERFORM hafbe_app.process_transaction_stats(_from, _to);
  PERFORM hafbe_app.process_witness_stats(_from, _to);
  PERFORM hafbe_app.process_witness_votes(_from, _to);

  IF _logs THEN
    __end_ts := clock_timestamp();
    RAISE NOTICE 'Hafbe processed block range: <%, %> successfully in % s
    ', _from, _to, (extract(epoch FROM __end_ts - __start_ts));
  END IF;
END
$$;

CREATE OR REPLACE PROCEDURE hafbe_app.single_processing(
    IN _block INT,
    IN _logs BOOLEAN
)
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __start_ts timestamptz;
  __end_ts   timestamptz;
BEGIN
  PERFORM set_config('synchronous_commit', 'ON', false);

  IF _logs THEN
    RAISE NOTICE 'Hafbe processing block: %...', _block;
    __start_ts := clock_timestamp();
  END IF;

  PERFORM hafbe_app.process_account_stats(_block, _block);
  PERFORM hafbe_app.process_block_operations(_block, _block);
  PERFORM hafbe_app.process_transaction_stats(_block, _block);
  PERFORM hafbe_app.process_witness_stats(_block, _block);
  PERFORM hafbe_app.process_witness_votes(_block, _block);
  PERFORM hafbe_app.process_witness_votes_cache();

  IF _logs THEN
    __end_ts := clock_timestamp();
    RAISE NOTICE 'Hafbe processed block % successfully in % s
    ', _block, (extract(epoch FROM __end_ts - __start_ts));
  END IF;
END
$$;


CREATE OR REPLACE FUNCTION hafbe_app.log_and_process_blocks(
    _context_hafbe hive.context_name,
    _context_btracker hive.context_name,
    _block_range hive.blocks_range
)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS
$$
DECLARE
  __start_ts timestamptz;
  __end_ts   timestamptz;
  _time JSONB = '{}'::JSONB;
BEGIN
  IF hive.get_current_stage_name(_context_hafbe) = 'MASSIVE_PROCESSING' THEN
    RAISE NOTICE '[MASSIVE] Attempting to process a block range: <%, %>', _block_range.first_block, _block_range.last_block;
  ELSE
    RAISE NOTICE '[SINGLE]  Attempting to process block: <%>', _block_range.first_block;
  END IF;

  SELECT hafbe_backend.get_sync_time(_time, 'time_on_start') INTO _time;
  PERFORM btracker_process_blocks(_context_btracker, _block_range, false);
  SELECT hafbe_backend.get_sync_time(_time, 'btracker') INTO _time;

  SELECT hafbe_backend.get_sync_time(_time, 'time_on_start') INTO _time;
  PERFORM hafbe_app.process_blocks(_context_hafbe, _block_range, false);
  SELECT hafbe_backend.get_sync_time(_time, 'hafbe') INTO _time;

  SELECT hafbe_backend.get_sync_time(_time, 'time_on_start') INTO _time;
  PERFORM hive.app_state_providers_update(_block_range.first_block, _block_range.last_block, _context_hafbe);
  SELECT hafbe_backend.get_sync_time(_time, 'state_provider') INTO _time;

  INSERT INTO hafbe_app.sync_time_logs (block_num, time_json) VALUES (_block_range.first_block, _time);

  RAISE NOTICE 'Processed blocks in % seconds',
  ROUND(EXTRACT(epoch FROM (SELECT clock_timestamp() - last_reported_at FROM hafbe_app.app_status LIMIT 1)), 3);
  UPDATE hafbe_app.app_status SET last_reported_at = clock_timestamp();

  RAISE NOTICE 'Block processing running for % minutes
  ',
  ROUND((EXTRACT(epoch FROM (SELECT clock_timestamp() - started_processing_at FROM hafbe_app.app_status LIMIT 1)) / 60)::NUMERIC, 2);

END
$$;

-- =============================================================================
-- SECTION 5: MAIN ENTRY POINT
-- =============================================================================

/** Application entry point, which:
  - defines its data schema,
  - creates HAF application context,
  - starts application main-loop (which iterates infinitely).
    To stop it call `hafbe_app.stopProcessing();` from another session and commit its trasaction.
*/
CREATE OR REPLACE PROCEDURE hafbe_app.main(
    IN _appContext hive.context_name,
    IN _appContext_btracker hive.context_name,
    IN _maxBlockLimit INT = NULL
)
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  _blocks_range hive.blocks_range := (0,0);
BEGIN
  IF _maxBlockLimit != NULL THEN
    RAISE NOTICE 'Max block limit is specified as: %', _maxBlockLimit;
  END IF;

  --used in time logs
  UPDATE hafbe_app.app_status
  SET last_reported_at = clock_timestamp(),
      started_processing_at = clock_timestamp();

  PERFORM hafbe_app.allowProcessing();

  RAISE NOTICE 'Last block processed by application: %', hive.app_get_current_block_num(_appContext);

  RAISE NOTICE 'Entering application main loop...';

  LOOP
    CALL hive.app_next_iteration(
      ARRAY[_appContext, _appContext_btracker],
      _blocks_range,
      _override_max_batch => NULL,
      _limit => _maxBlockLimit);

    IF NOT hafbe_app.continueProcessing() THEN
      ROLLBACK;
      RAISE NOTICE 'Exiting application main loop at processed block: %.', hive.app_get_current_block_num(_appContext);
      RETURN;
    END IF;

    IF _blocks_range IS NULL THEN
      RAISE INFO 'Waiting for next block...';
      CONTINUE;
    END IF;

    PERFORM hafbe_app.log_and_process_blocks(_appContext, _appContext_btracker, _blocks_range);
  END LOOP;

  ASSERT FALSE, 'Cannot reach this point';
END
$$;


RESET ROLE;
