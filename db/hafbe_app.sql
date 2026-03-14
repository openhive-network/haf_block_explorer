-- noqa: disable=CP03
/**
 * HAF Block Explorer Core Application Schema
 * ==========================================
 *
 * This file defines the core HAF Block Explorer application, including:
 * - HAF context registration and synchronization stages
 * - All database tables for tracking block/witness/account data
 * - Control functions for application lifecycle
 * - Block processing dispatch functions
 * - Index creation for API performance
 *
 * Table Groups:
 * -------------
 * 1. CONTROL TABLES
 *    - app_status: Processing control flag and timing info
 *    - version: Schema version tracking (git hash)
 *
 * 2. BLOCK OPERATIONS
 *    - block_operations: Aggregated operation counts per block/type
 *
 * 3. ACCOUNT PARAMETERS
 *    - account_parameters: Account metadata cache (voting, mining, recovery)
 *
 * 4. WITNESS VOTES & PROXIES
 *    - witness_votes_history: Complete vote change history
 *    - current_witness_votes: Current active witness votes
 *    - account_proxies_history: Complete proxy change history
 *    - current_account_proxies: Current proxy assignments
 *
 * 5. TRANSACTION STATISTICS
 *    - transaction_stats_by_month: Monthly aggregated transaction stats
 *    - transaction_stats_by_day: Daily aggregated transaction stats
 *
 * 6. WITNESS STATISTICS
 *    - current_witnesses: Witness metadata (url, price feed, version, etc.)
 *
 * 7. SYNC LOGGING
 *    - sync_time_logs: Performance metrics for block processing
 *
 * 8. CACHE TABLES (LIVE stage only)
 *    - account_vest_stats_cache: Cached vest statistics per account
 *    - witness_votes_cache: Cached witness vote counts
 *    - witness_rank_cache: Cached witness rankings
 *    - witness_votes_change_cache: Cached daily vote changes
 *
 * HAF Synchronization Stages:
 * ---------------------------
 * - MASSIVE_PROCESSING: Initial sync, processes blocks in batches of 10000
 * - LIVE: Real-time sync, processes blocks one at a time
 *
 * Processing Flow:
 * ----------------
 * 1. main() starts the application loop (handles both hafbe + btracker contexts)
 * 2. log_and_process_blocks() orchestrates timing and both processors
 * 3. process_blocks() dispatches to massive or single processing
 * 4. Individual process_* functions handle specific data types
 *
 * @see builtin_roles.sql for database role definitions
 * @see db/process_*.sql files for individual processing logic
 */

SET ROLE hafbe_owner;

-- ============================================================================
-- SCHEMA AND TABLE CREATION
-- ============================================================================

DO $$
  DECLARE synchronization_stages hive.application_stages;
BEGIN
  -- Check if context already exists - if so, skip table creation
  IF hive.app_context_exists('hafbe_app') THEN
    RAISE NOTICE 'Context hafbe_app already exists, skipping table creation';
    RETURN;
  END IF;

  CREATE SCHEMA IF NOT EXISTS hafbe_app AUTHORIZATION hafbe_owner;

  synchronization_stages := ARRAY[hive.stage( 'MASSIVE_PROCESSING', 101, 10000, '20 seconds' ), hive.live_stage()]::hive.application_stages;

  PERFORM hive.app_create_context(
     _name =>'hafbe_app',
     _schema => 'hafbe_app',
     _is_forking => current_setting('custom.is_forking')::BOOLEAN,
     _stages => synchronization_stages
  );

  RAISE NOTICE 'Attempting to create an application schema tables...';

  -- Register state providers for hafbe_app
  PERFORM hive.app_state_provider_import('METADATA', 'hafbe_app');
  PERFORM hive.app_state_provider_import('KEYAUTH',  'hafbe_app');

  ------------- CONTROL TABLES ----------------

  /*
   * app_status: Processing control and timing state
   * ------------------------------------------------
   * Single-row table controlling the main processing loop lifecycle.
   * Used by scripts/process_blocks.sh to start/stop block processing.
   */
  CREATE TABLE IF NOT EXISTS hafbe_app.app_status (
    continue_processing   BOOLEAN   NULL,  -- FALSE signals main loop to exit gracefully
    started_processing_at TIMESTAMP NULL,  -- When current processing session began
    last_reported_at      TIMESTAMP NULL,  -- Last progress report timestamp (for timing)
    if_hf11               BOOLEAN   NULL,  -- TRUE after hardfork 11 has been processed
    blocksearch_indexes   BOOLEAN   NOT NULL DEFAULT FALSE  -- TRUE to create optional block search indexes
  );

  INSERT INTO hafbe_app.app_status (continue_processing, started_processing_at, last_reported_at, if_hf11, blocksearch_indexes)
  VALUES (TRUE, NULL, NULL, FALSE, FALSE);

  /*
   * version: Schema version tracking
   * --------------------------------
   * Stores the git hash of the deployed schema for debugging and audit.
   * Updated by scripts/set_version_in_sql.pgsql during deployment.
   */
  CREATE TABLE IF NOT EXISTS hafbe_app.version (
    git_hash TEXT NULL  -- Git commit hash of deployed schema version
  );

  INSERT INTO hafbe_app.version VALUES('unspecified (generate and apply set_version_in_sql.pgsql)');

  ------------- BLOCK OPERATIONS ----------------

  /*
   * block_operations: Aggregated operation counts per block
   * -------------------------------------------------------
   * Pre-computed counts of each operation type per block for fast API queries.
   * Populated by process_block_operations() during block sync.
   * Used by get_op_count_in_block() and block statistics endpoints.
   */
  CREATE TABLE IF NOT EXISTS hafbe_app.block_operations (
    block_num  INT NOT NULL,  -- Block number containing the operations
    op_type_id INT NOT NULL,  -- Operation type ID (from hive.operation_types)
    op_count   INT NOT NULL   -- Count of this operation type in the block
  );

  PERFORM hive.app_register_table( 'hafbe_app', 'block_operations', 'hafbe_app' );

  ------------- ACCOUNT PARAMETERS ----------------

  /*
   * account_parameters: Account metadata cache
   * ------------------------------------------
   * Stores computed account properties extracted from various operations.
   * Populated by process_account_stats() during block sync.
   *
   * NULL HANDLING: Columns allow NULL to indicate "unknown/not yet processed".
   * API layer uses COALESCE with hafbe_backend constants to provide defaults:
   *   - hafbe_backend.default_can_vote()
   *   - hafbe_backend.default_mined()
   *   - hafbe_backend.default_recovery_account()
   *   - hafbe_backend.default_timestamp()
   *   - hafbe_backend.default_pending_claimed_accounts()
   */
  CREATE TABLE IF NOT EXISTS hafbe_app.account_parameters (
    account                  INT       NOT NULL,  -- Account ID (FK to hive.accounts_view)
    can_vote                 BOOLEAN   NULL,      -- FALSE if decline_voting_rights was set
    mined                    BOOLEAN   NULL,      -- TRUE if account was created via PoW mining
    recovery_account         TEXT      NULL,      -- Designated recovery account name
    last_account_recovery    TIMESTAMP NULL,      -- When account was last recovered
    created                  TIMESTAMP NULL,      -- Account creation timestamp
    pending_claimed_accounts INT       NULL,      -- Unclaimed account creation tokens

    CONSTRAINT pk_account_parameters PRIMARY KEY (account)
  );

  PERFORM hive.app_register_table( 'hafbe_app', 'account_parameters', 'hafbe_app' );

  ------------- WITNESS VOTES & PROXIES ----------------

  /*
   * witness_votes_history: Complete witness vote change history
   * -----------------------------------------------------------
   * Append-only log of all witness vote changes (approvals and removals).
   * Used by get_witness_votes_history() for vote timeline queries.
   * Populated by process_witness_votes() during block sync.
   */
  CREATE TABLE IF NOT EXISTS hafbe_app.witness_votes_history (
    witness_id INT     NOT NULL,  -- Witness account ID being voted for
    voter_id   INT     NOT NULL,  -- Account ID casting the vote
    approve    BOOLEAN NOT NULL,  -- TRUE=vote added, FALSE=vote removed
    source_op  BIGINT  NOT NULL   -- Operation ID that triggered this change
  );
  PERFORM hive.app_register_table( 'hafbe_app', 'witness_votes_history', 'hafbe_app' );

  /*
   * current_witness_votes: Current active witness votes
   * ----------------------------------------------------
   * Snapshot of currently active votes (only approved, not removed).
   * Updated via UPSERT/DELETE by process_witness_votes().
   * Used by get_witness_voters() and vote count queries.
   */
  CREATE TABLE IF NOT EXISTS hafbe_app.current_witness_votes (
    voter_id   INT    NOT NULL,  -- Account ID that cast the vote
    witness_id INT    NOT NULL,  -- Witness account ID being voted for
    source_op  BIGINT NOT NULL,  -- Operation ID of the vote

    CONSTRAINT pk_current_witness_votes PRIMARY KEY (voter_id, witness_id)
  );
  PERFORM hive.app_register_table( 'hafbe_app', 'current_witness_votes', 'hafbe_app' );

  /*
   * account_proxies_history: Complete proxy change history
   * ------------------------------------------------------
   * Append-only log of all proxy setting changes.
   * Used by get_account_proxy_history() for proxy timeline queries.
   * Populated by process_witness_votes() during block sync.
   */
  CREATE TABLE IF NOT EXISTS hafbe_app.account_proxies_history (
    account_id INT     NOT NULL,  -- Account ID setting the proxy
    proxy_id   INT     NOT NULL,  -- Account ID being set as proxy
    proxy      BOOLEAN NOT NULL,  -- TRUE=proxy set, FALSE=proxy cleared
    source_op  BIGINT  NOT NULL   -- Operation ID that triggered this change
  );
  PERFORM hive.app_register_table( 'hafbe_app', 'account_proxies_history', 'hafbe_app' );

  /*
   * current_account_proxies: Current proxy assignments
   * --------------------------------------------------
   * Snapshot of currently active proxy relationships.
   * One account can have at most one proxy (enforced by PK).
   * Updated via UPSERT/DELETE by process_witness_votes().
   */
  CREATE TABLE IF NOT EXISTS hafbe_app.current_account_proxies (
    account_id INT    NOT NULL,  -- Account ID that delegated voting
    proxy_id   INT    NOT NULL,  -- Account ID receiving delegated votes
    source_op  BIGINT NOT NULL,  -- Operation ID of the proxy assignment

    CONSTRAINT pk_current_account_proxies PRIMARY KEY (account_id)
  );
  PERFORM hive.app_register_table( 'hafbe_app', 'current_account_proxies', 'hafbe_app' );

  ------------- TRANSACTION STATISTICS ----------------

  /*
   * transaction_stats_by_month: Monthly aggregated transaction statistics
   * ---------------------------------------------------------------------
   * Pre-aggregated monthly transaction counts for dashboard queries.
   * One row per month (keyed by first day of month in updated_at).
   * Populated by process_transaction_stats() during block sync.
   */
  CREATE TABLE IF NOT EXISTS hafbe_app.transaction_stats_by_month (
    trx_count      INT       NOT NULL,  -- Total transactions in the month
    count_blocks   INT       NOT NULL,  -- Number of blocks processed in month
    min_trx        INT       NOT NULL,  -- Minimum transactions in a single block
    max_trx        INT       NOT NULL,  -- Maximum transactions in a single block
    last_block_num INT       NOT NULL,  -- Last block number included in stats
    updated_at     TIMESTAMP NOT NULL,  -- First day of month (serves as PK)

    CONSTRAINT pk_transaction_stats_by_month PRIMARY KEY (updated_at)
  );
  PERFORM hive.app_register_table( 'hafbe_app', 'transaction_stats_by_month', 'hafbe_app' );

  /*
   * transaction_stats_by_day: Daily aggregated transaction statistics
   * -----------------------------------------------------------------
   * Pre-aggregated daily transaction counts for dashboard queries.
   * One row per day (keyed by date in updated_at).
   * Populated by process_transaction_stats() during block sync.
   */
  CREATE TABLE IF NOT EXISTS hafbe_app.transaction_stats_by_day (
    trx_count      INT       NOT NULL,  -- Total transactions on this day
    count_blocks   INT       NOT NULL,  -- Number of blocks processed on this day
    min_trx        INT       NOT NULL,  -- Minimum transactions in a single block
    max_trx        INT       NOT NULL,  -- Maximum transactions in a single block
    last_block_num INT       NOT NULL,  -- Last block number included in stats
    updated_at     TIMESTAMP NOT NULL,  -- Date of statistics (serves as PK)

    CONSTRAINT pk_transaction_stats_by_day PRIMARY KEY (updated_at)
  );
  PERFORM hive.app_register_table( 'hafbe_app', 'transaction_stats_by_day', 'hafbe_app' );

  ------------- WITNESS STATISTICS ----------------

  /*
   * current_witnesses: Witness metadata and configuration
   * -----------------------------------------------------
   * Stores current witness properties extracted from witness_update operations.
   * Updated by process_witness_stats() during block sync.
   * Used by get_witness() and witness listing endpoints.
   */
  CREATE TABLE IF NOT EXISTS hafbe_app.current_witnesses (
    witness_id             INT       NOT NULL,  -- Witness account ID (PK)
    url                    TEXT      NULL,      -- Witness URL/website from witness_update
    price_feed             FLOAT     NULL,      -- Current HIVE/HBD price feed value
    bias                   NUMERIC   NULL,      -- Price feed bias percentage
    feed_updated_at        TIMESTAMP NULL,      -- When price feed was last published
    block_size             INT       NULL,      -- Preferred maximum block size
    signing_key            TEXT      NULL,      -- Public signing key for block production
    version                TEXT      NULL,      -- Witness node software version
    hbd_interest_rate      INT       NULL,      -- Proposed HBD interest rate (basis points)
    last_created_block_num INT       NULL,      -- Most recent block produced by witness
    account_creation_fee   INT       NULL,      -- Fee for creating accounts (in HIVE)
    missed_blocks          INT       NULL,      -- Cumulative count of missed blocks
    created                TIMESTAMP NULL,      -- When witness was first registered

    CONSTRAINT pk_current_witnesses PRIMARY KEY (witness_id)
  );
  PERFORM hive.app_register_table( 'hafbe_app', 'current_witnesses', 'hafbe_app' );

  ------------- SYNC LOGGING ----------------

  /*
   * sync_time_logs: Block processing performance metrics
   * ----------------------------------------------------
   * Stores timing data for each processed block range.
   * Used for performance monitoring and optimization.
   * Populated by log_and_process_blocks() during sync.
   */
  CREATE TABLE IF NOT EXISTS hafbe_app.sync_time_logs (
    block_num INT   NOT NULL,  -- First block of the processed range (PK)
    time_json JSONB NOT NULL,  -- JSON with timing breakdown (btracker, hafbe, state_provider)

    CONSTRAINT pk_massive_sync_time_logs PRIMARY KEY (block_num)
  );
  PERFORM hive.app_register_table( 'hafbe_app', 'sync_time_logs', 'hafbe_app' );

  ------------- CACHE TABLES (LIVE stage only) ----------------
  /*
   * Cache tables are populated exclusively during LIVE synchronization.
   * They provide fast access to computed values that would otherwise
   * require expensive joins across multiple tables.
   *
   * Updated by process_witness_votes_cache() at each block during live sync.
   * Truncated/rebuilt at each block to ensure consistency.
   */

  /*
   * account_vest_stats_cache: Cached vest statistics per account
   * ------------------------------------------------------------
   * Pre-computed voting power for accounts (voters and proxies).
   * Used by witness vote weight calculations.
   */
  CREATE TABLE IF NOT EXISTS hafbe_app.account_vest_stats_cache (
    account_id    INT    NOT NULL,  -- Account ID (PK)
    vests         BIGINT NOT NULL,  -- Total effective vests (account + proxied)
    account_vests BIGINT NOT NULL,  -- Account's own vesting shares
    proxied_vests BIGINT NOT NULL,  -- Vests delegated via proxy

    CONSTRAINT pk_account_vest_stats_cache PRIMARY KEY (account_id)
  );

  /*
   * witness_votes_cache: Cached witness vote totals
   * -----------------------------------------------
   * Pre-computed total votes and voter counts per witness.
   * Used by get_witnesses() for sorting by votes.
   */
  CREATE TABLE IF NOT EXISTS hafbe_app.witness_votes_cache (
    witness_id INT    NOT NULL,  -- Witness account ID (PK)
    votes      BIGINT NOT NULL,  -- Total weighted votes (sum of voter vests)
    voters_num INT    NOT NULL,  -- Count of unique voters

    CONSTRAINT pk_witness_votes_cache PRIMARY KEY (witness_id)
  );

  /*
   * witness_rank_cache: Cached witness rankings
   * -------------------------------------------
   * Pre-computed witness rank based on total votes.
   * Rank 1 = most votes. Used for witness listing display.
   */
  CREATE TABLE IF NOT EXISTS hafbe_app.witness_rank_cache (
    witness_id INT NOT NULL,  -- Witness account ID (PK)
    rank       INT NOT NULL,  -- Current rank (1 = highest votes)

    CONSTRAINT pk_witness_rank_cache PRIMARY KEY (witness_id)
  );

  /*
   * witness_votes_change_cache: Cached daily vote changes
   * -----------------------------------------------------
   * Pre-computed 24-hour changes in votes and voter counts.
   * Used by get_witnesses() for showing vote trends.
   */
  CREATE TABLE IF NOT EXISTS hafbe_app.witness_votes_change_cache (
    witness_id              INT    NOT NULL,  -- Witness account ID (PK)
    votes_daily_change      BIGINT NOT NULL,  -- Change in votes over last 24h
    voters_num_daily_change INT    NOT NULL,  -- Change in voter count over last 24h

    CONSTRAINT pk_witness_votes_change_cache PRIMARY KEY (witness_id)
  );

  ------------- SWITCH TO NON-FORKING FOR MASSIVE SYNC ----------------
  -- Context is created as forking (required for state provider table registration),
  -- but we switch to non-forking now to avoid creating hive_rowid indexes
  -- during massive sync. Will switch back to forking at LIVE transition.
  --
  -- IMPORTANT: set_non_forking detaches/reattaches the context at the current
  -- irreversible block, which would skip all block processing if HAF already has data.
  -- We must detach and reset the position to 0 so processing starts from the beginning.
  -- app_next_iteration() will auto-attach when processing begins.
  PERFORM hive.app_context_set_non_forking('hafbe_app');
  PERFORM hive.app_context_detach('hafbe_app');
  PERFORM hive.app_set_current_block_num('hafbe_app', 0);

END
$$;

-- ============================================================================
-- CONTROL FUNCTIONS
-- ============================================================================
-- These functions manage the application processing lifecycle.
-- Used by scripts/process_blocks.sh to control block processing.

/**
 * continueProcessing()
 * --------------------
 * Check if the application should continue processing blocks.
 * Called in the main loop to allow graceful shutdown.
 *
 * @returns TRUE if processing should continue, FALSE to stop
 */
CREATE OR REPLACE FUNCTION hafbe_app.continueProcessing()
RETURNS BOOLEAN
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN continue_processing FROM hafbe_app.app_status LIMIT 1;
END
$$;

/**
 * allowProcessing()
 * -----------------
 * Enable block processing. Called at application startup
 * to reset the processing flag after a previous stop.
 */
CREATE OR REPLACE FUNCTION hafbe_app.allowProcessing()
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
  UPDATE hafbe_app.app_status SET continue_processing = True;
END
$$;

/**
 * stopProcessing()
 * ----------------
 * Signal the application to stop processing after the current block.
 * Must be called from a separate session and committed to take effect.
 * The main loop will exit gracefully on next iteration check.
 *
 * Usage: Call from psql or separate connection, then COMMIT.
 */
CREATE OR REPLACE FUNCTION hafbe_app.stopProcessing()
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
  UPDATE hafbe_app.app_status SET continue_processing = False;
END
$$;

/**
 * isIndexesCreated()
 * ------------------
 * Check if hafbe performance indexes have been created.
 * Used to determine if we're transitioning from MASSIVE to LIVE stage.
 * Indexes are created once before entering LIVE processing.
 *
 * @returns TRUE if indexes exist, FALSE otherwise
 */
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

/**
 * isCommentSearchIndexesCreated()
 * -------------------------------
 * Check if comment search indexes exist on hive operations.
 * Used by validators to verify comment search capability is available.
 *
 * @returns TRUE if comment search indexes exist, FALSE otherwise
 */
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

/**
 * isBlockSearchIndexesCreated()
 * -----------------------------
 * Check if block search indexes exist on hive operations.
 * Used by validators to verify block search capability is available.
 *
 * @returns TRUE if block search indexes exist, FALSE otherwise
 */
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

-- ============================================================================
-- BLOCK PROCESSING FUNCTIONS
-- ============================================================================
-- These functions handle block processing dispatch and execution.
-- Called by the main loop for each block range to sync.

/**
 * process_blocks()
 * ----------------
 * Main dispatch function for block processing.
 * Routes to either massive or single processing based on current HAF stage.
 *
 * Behavior by stage:
 * - MASSIVE_PROCESSING: Calls massive_processing() for batch sync,
 *   requests vacuum on witness/proxy tables
 * - LIVE: Creates indexes (once), calls single_processing(),
 *   requests vacuum on cache tables
 *
 * @param _context_name  HAF context name (typically 'hafbe_app')
 * @param _block_range   Range of blocks to process (first_block, last_block)
 * @param _logs          Enable progress logging (default: true)
 */
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
    PERFORM hafbe_app.create_hafbe_indexes();
  END IF;
  CALL hafbe_app.single_processing(_block_range.first_block, _logs);
  -- cache tables needs to be vacuumed, due to change from `TRUNCATE TABLE` to `DELETE FROM` in block processing
  PERFORM hive.app_request_table_vacuum('hafbe_app', 'account_vest_stats_cache',   interval '10 minutes');
  PERFORM hive.app_request_table_vacuum('hafbe_app', 'witness_votes_cache',        interval '10 minutes');
  PERFORM hive.app_request_table_vacuum('hafbe_app', 'witness_rank_cache',         interval '10 minutes');
  PERFORM hive.app_request_table_vacuum('hafbe_app', 'witness_votes_change_cache', interval '10 minutes');
END
$$;

/**
 * massive_processing()
 * --------------------
 * Process a range of blocks during initial sync (MASSIVE_PROCESSING stage).
 * Optimized for throughput with synchronous_commit OFF.
 *
 * Processing order per range:
 * 1. Account stats (account_parameters updates)
 * 2. Block operations (operation counts aggregation)
 * 3. Transaction stats (daily/monthly aggregations)
 * 4. Witness stats (witness metadata updates)
 * 5. Witness votes (vote history and current state)
 *
 * @param _from  First block number to process
 * @param _to    Last block number to process
 * @param _logs  Enable progress logging
 */
CREATE OR REPLACE PROCEDURE hafbe_app.massive_processing(
    IN _from INT,
    IN _to INT,
    IN _logs BOOLEAN
)
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __start_ts TIMESTAMPTZ;
  __end_ts   TIMESTAMPTZ;
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

/**
 * single_processing()
 * -------------------
 * Process a single block during LIVE sync stage.
 * Uses synchronous_commit ON for data safety.
 *
 * Called for each new block after initial sync is complete.
 * Processes all operation types for the given block plus cache updates.
 *
 * @param _block  Block number to process
 * @param _logs   Enable progress logging
 */
CREATE OR REPLACE PROCEDURE hafbe_app.single_processing(
    IN _block INT,
    IN _logs BOOLEAN
)
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __start_ts TIMESTAMPTZ;
  __end_ts   TIMESTAMPTZ;
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

/**
 * log_and_process_blocks()
 * ------------------------
 * High-level orchestrator that coordinates multi-component processing.
 * Manages both Balance Tracker and HAF Block Explorer processing with timing.
 *
 * Execution sequence:
 * 1. Log block range or block number (based on stage)
 * 2. Call btracker_process_blocks() (Balance Tracker) - measure time
 * 3. Call hafbe_app.process_blocks() (HAF Block Explorer) - measure time
 * 4. Call hive.app_state_providers_update() (HAF core state) - measure time
 * 5. Insert timing metrics into sync_time_logs
 * 6. Update app_status with reporting timestamps
 *
 * @param _context_hafbe    HAF context name for hafbe
 * @param _context_btracker HAF context name for balance tracker
 * @param _block_range      Range of blocks to process
 */
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
  __start_ts TIMESTAMPTZ;
  __end_ts   TIMESTAMPTZ;
  _time      JSONB = '{}'::JSONB;
BEGIN
  IF hive.get_current_stage_name(_context_hafbe) = 'MASSIVE_PROCESSING' THEN
    RAISE NOTICE '[MASSIVE] Attempting to process a block range: <%, %>', _block_range.first_block, _block_range.last_block;
  ELSE
    -- Transition both contexts to forking together on first LIVE block.
    -- This MUST happen here (not in individual processors) because
    -- set_forking reattaches contexts at irreversible_block. If only one
    -- context transitions, they desync and app_next_iteration fails with
    -- "Contexts {hafbe_app,hafbe_bal} are not synchronized".
    -- Idempotent in HAF: no-op after first LIVE block.
    PERFORM hive.app_context_set_forking(ARRAY[_context_hafbe, _context_btracker]);
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

-- ============================================================================
-- APPLICATION ENTRY POINT
-- ============================================================================

/**
 * main()
 * ------
 * Application entry point that starts the block processing loop.
 * Called by scripts/process_blocks.sh to begin syncing.
 *
 * Behavior:
 * 1. Initializes timing timestamps in app_status
 * 2. Enables processing via allowProcessing()
 * 3. Enters infinite loop calling hive.app_next_iteration()
 * 4. Processes each block range via log_and_process_blocks()
 * 5. Exits when continueProcessing() returns FALSE
 *
 * To stop: Call stopProcessing() from another session and commit.
 *
 * @param _appContext         HAF context name for hafbe
 * @param _appContext_btracker HAF context name for balance tracker
 * @param _maxBlockLimit      Optional maximum block to process (for testing)
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

-- ============================================================================
-- INDEX CREATION
-- ============================================================================

/**
 * register_haf_indexes()
 * -----------------------
 * Register indexes on HAF tables (hafd.operations, hafd.blocks)
 * that are needed by hafbe's API endpoints.
 *
 * These indexes are deferred until after hafbe finishes its MASSIVE sync,
 * rather than being registered at install time. This prevents hived's
 * enable_indexes_of_irreversible() from building them during replay,
 * which would block all apps from starting their own sync.
 *
 * Only registers the indexes (status='missing' in hafd.indexes_constraints).
 * The actual creation is handled by hived's poll_and_create_indexes() background
 * thread, which builds them with CREATE INDEX CONCURRENTLY to avoid blocking
 * hived's writes or other apps.
 */
CREATE OR REPLACE FUNCTION hafbe_app.register_haf_indexes()
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS
$$
DECLARE
  __blocksearch BOOLEAN;
BEGIN
  SELECT blocksearch_indexes INTO __blocksearch FROM hafbe_app.app_status LIMIT 1;

  RAISE NOTICE 'Registering HAF index dependencies for hafbe_app...';

  -- Always-on: block hash lookup (used by get_input_type)
  PERFORM hive.app_register_index_dependency(
    'hafbe_app',
    'CREATE UNIQUE INDEX IF NOT EXISTS uq_blocks_hash ON hafd.blocks USING btree (hash)'
  );

  -- Always-on: comment search indexes
  PERFORM hive.app_register_index_dependency(
    'hafbe_app',
    $$
    CREATE INDEX IF NOT EXISTS hive_operations_comment_search_permlink ON hafd.operations USING btree
    (
        (body_value ->>'author'),
        hafd.operation_id_to_block_num(id) DESC
    )
    WHERE op_type_id = 1
    $$
  );

  PERFORM hive.app_register_index_dependency(
    'hafbe_app',
    $$
    CREATE INDEX IF NOT EXISTS hive_operations_comment_search_permlink_parent_author ON hafd.operations USING btree
    (
        (body_value ->>'author'),
        (body_value ->>'parent_author'),
        hafd.operation_id_to_block_num(id) DESC
    )
    WHERE op_type_id = 1
    $$
  );

  PERFORM hive.app_register_index_dependency(
    'hafbe_app',
    $$
    CREATE INDEX IF NOT EXISTS hive_operations_comment_search_permlink_author ON hafd.operations USING btree
    (
        (body_value ->>'author'),
        (body_value ->>'permlink')
    )
    WHERE op_type_id IN (0, 1, 17, 19, 51, 52, 53, 61, 63, 72, 73)
    $$
  );

  -- Optional: block search indexes
  IF __blocksearch THEN
    RAISE NOTICE 'Registering block search indexes...';

    PERFORM hive.app_register_index_dependency('hafbe_app',
      $idx$CREATE INDEX IF NOT EXISTS hive_operations_vote_author_permlink ON hafd.operations USING btree (jsonb_extract_path_text(body_value,'author'), jsonb_extract_path_text(body_value,'permlink')) WHERE op_type_id = 0$idx$);

    PERFORM hive.app_register_index_dependency('hafbe_app',
      $idx$CREATE INDEX IF NOT EXISTS hive_operations_comment_author_permlink ON hafd.operations USING btree (jsonb_extract_path_text(body_value,'author'), jsonb_extract_path_text(body_value,'permlink')) WHERE op_type_id = 1$idx$);

    PERFORM hive.app_register_index_dependency('hafbe_app',
      $idx$CREATE INDEX IF NOT EXISTS hive_operations_comment_parent_author_permlink ON hafd.operations USING btree (jsonb_extract_path_text(body_value,'parent_author'), jsonb_extract_path_text(body_value,'parent_permlink')) WHERE op_type_id = 1$idx$);

    PERFORM hive.app_register_index_dependency('hafbe_app',
      $idx$CREATE INDEX IF NOT EXISTS hive_operations_delete_comment_author_permlink ON hafd.operations USING btree (jsonb_extract_path_text(body_value,'author'), jsonb_extract_path_text(body_value,'permlink')) WHERE op_type_id IN (17, 73)$idx$);

    PERFORM hive.app_register_index_dependency('hafbe_app',
      $idx$CREATE INDEX IF NOT EXISTS hive_operations_comment_options_author_permlink ON hafd.operations USING btree (jsonb_extract_path_text(body_value,'author'), jsonb_extract_path_text(body_value,'permlink')) WHERE op_type_id = 19$idx$);

    PERFORM hive.app_register_index_dependency('hafbe_app',
      $idx$CREATE INDEX IF NOT EXISTS hive_operations_author_reward_author_permlink ON hafd.operations USING btree (jsonb_extract_path_text(body_value,'author'), jsonb_extract_path_text(body_value,'permlink')) WHERE op_type_id = 51$idx$);

    PERFORM hive.app_register_index_dependency('hafbe_app',
      $idx$CREATE INDEX IF NOT EXISTS hive_operations_curation_author_permlink ON hafd.operations USING btree (jsonb_extract_path_text(body_value,'author'), jsonb_extract_path_text(body_value,'permlink')) WHERE op_type_id = 52$idx$);

    PERFORM hive.app_register_index_dependency('hafbe_app',
      $idx$CREATE INDEX IF NOT EXISTS hive_operations_comment_benefactor_author_permlink ON hafd.operations USING btree (jsonb_extract_path_text(body_value,'author'), jsonb_extract_path_text(body_value,'permlink')) WHERE op_type_id = 63$idx$);

    PERFORM hive.app_register_index_dependency('hafbe_app',
      $idx$CREATE INDEX IF NOT EXISTS hive_operations_comment_payout_author_permlink ON hafd.operations USING btree (jsonb_extract_path_text(body_value,'author'), jsonb_extract_path_text(body_value,'permlink')) WHERE op_type_id = 61$idx$);

    PERFORM hive.app_register_index_dependency('hafbe_app',
      $idx$CREATE INDEX IF NOT EXISTS hive_operations_comment_reward_author_permlink ON hafd.operations USING btree (jsonb_extract_path_text(body_value,'author'), jsonb_extract_path_text(body_value,'permlink')) WHERE op_type_id = 53$idx$);

    PERFORM hive.app_register_index_dependency('hafbe_app',
      $idx$CREATE INDEX IF NOT EXISTS hive_operations_effective_vote_author_permlink ON hafd.operations USING btree (jsonb_extract_path_text(body_value,'author'), jsonb_extract_path_text(body_value,'permlink')) WHERE op_type_id = 72$idx$);
  ELSE
    RAISE NOTICE 'Skipping block search indexes (blocksearch_indexes is false).';
  END IF;

  RAISE NOTICE 'HAF indexes registered. hived will create them concurrently in the background.';
END
$$;

/**
 * create_hafbe_indexes()
 * ----------------------
 * Create performance indexes on hafbe's own tables and HAF tables for API queries.
 * Called once when transitioning from MASSIVE to LIVE processing.
 *
 * Indexes are deferred until after initial sync because:
 * 1. Building indexes on empty/small tables is fast
 * 2. Maintaining indexes during bulk inserts is slow
 * 3. Better to bulk load then index
 *
 * Index Purposes:
 * ---------------
 * Witness Votes:
 *   - current_witness_votes_witness_id: Filter by witness
 *   - witness_votes_history_witness_id_source_op: Time-ordered history
 *   - witness_votes_history_witness_voter: Efficient voter filtering
 *
 * Account Proxies:
 *   - account_proxies_history_account_id_source_op: Time-ordered history (also serves account filtering)
 *   - current_account_proxies_proxy_id: Filter by proxy
 *
 * Block Operations:
 *   - block_operations_block_num: Filter by block
 *   - block_operations_op_type_id_block_num: Unique constraint on type+block
 */
CREATE OR REPLACE FUNCTION hafbe_app.create_hafbe_indexes()
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
  -- Indexes on hafbe_app's own tables
  CREATE INDEX IF NOT EXISTS current_witness_votes_witness_id ON hafbe_app.current_witness_votes USING btree (witness_id);

  --Can only vote once every 3 seconds, so sorting by block_num is sufficient
  CREATE INDEX IF NOT EXISTS witness_votes_history_witness_id_source_op ON hafbe_app.witness_votes_history USING btree (witness_id, hafd.operation_id_to_block_num( source_op ));

  -- Index for efficient voter filtering in get_witness_votes_history endpoint
  CREATE INDEX IF NOT EXISTS witness_votes_history_witness_voter ON hafbe_app.witness_votes_history USING btree (witness_id, voter_id);

  CREATE INDEX IF NOT EXISTS account_proxies_history_account_id_source_op ON hafbe_app.account_proxies_history USING btree (account_id, source_op);
  CREATE INDEX IF NOT EXISTS current_account_proxies_proxy_id ON hafbe_app.current_account_proxies USING btree (proxy_id);
  CREATE INDEX IF NOT EXISTS block_operations_block_num ON hafbe_app.block_operations USING btree (block_num);
  CREATE UNIQUE INDEX IF NOT EXISTS block_operations_op_type_id_block_num ON hafbe_app.block_operations USING btree (op_type_id, block_num);

  -- Register indexes on HAF tables (deferred from install time).
  -- hived's poll_and_create_indexes() will build them concurrently in the background.
  PERFORM hafbe_app.register_haf_indexes();
END
$$;

RESET ROLE;
