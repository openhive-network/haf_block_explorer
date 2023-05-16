
--- Helper function telling application main-loop to continue execution.
CREATE OR REPLACE FUNCTION hafbe_app.continueProcessing()
RETURNS BOOLEAN
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN continue_processing FROM hafbe_app.app_status LIMIT 1;
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_app.allowProcessing()
RETURNS VOID
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  UPDATE hafbe_app.app_status SET continue_processing = True;
END
$$
;

--- Helper function to be called from separate transaction (must be committed) to safely stop execution of the application.
CREATE OR REPLACE FUNCTION hafbe_app.stopProcessing()
RETURNS VOID
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  UPDATE hafbe_app.app_status SET continue_processing = False;
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_app.storeLastProcessedBlock(_lastBlock INT)
RETURNS VOID
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  UPDATE hafbe_app.app_status SET last_processed_block = _lastBlock;
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_app.lastProcessedBlock()
RETURNS INT
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN last_processed_block FROM hafbe_app.app_status LIMIT 1;
END
$$
;

CREATE OR REPLACE PROCEDURE hafbe_app.processBlock(_block INT)
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  PERFORM btracker_app.process_block_range_data_c(_block, _block);
  PERFORM hafbe_app.process_block_range_data_c(_block, _block);
  COMMIT; -- For single block processing we want to commit all changes for each one.
END
$$
;

CREATE OR REPLACE PROCEDURE hafbe_app.create_context_if_not_exists(_appContext VARCHAR)
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  IF NOT hive.app_context_exists(_appContext) THEN
    RAISE NOTICE 'Attempting to create a HAF application context...';
    PERFORM hive.app_create_context(_appContext);
    PERFORM hive.app_state_provider_import('METADATA', _appContext);
    COMMIT;
  END IF;
END
$$
;

CREATE OR REPLACE PROCEDURE hafbe_app.update_witnesses_cache()
AS
$function$
BEGIN
  RAISE NOTICE 'Updating witnesses caches';

  TRUNCATE TABLE hafbe_app.witness_voters_stats_cache;

  INSERT INTO hafbe_app.witness_voters_stats_cache (witness_id, voter_id, vests, account_vests, proxied_vests, timestamp)
  SELECT witness_id, voter_id, vests, account_vests, proxied_vests, timestamp
  FROM hafbe_views.voters_stats_view;

  RAISE NOTICE 'Updated witness voters cache';

  TRUNCATE TABLE hafbe_app.witness_votes_cache;

  INSERT INTO hafbe_app.witness_votes_cache (witness_id, rank, votes, voters_num)
  SELECT witness_id, RANK() OVER (ORDER BY votes DESC, voters_num DESC, feed_updated_at DESC), votes, voters_num
  FROM (
    SELECT
      witness_id,
      SUM(vests) AS votes,
      COUNT(1) AS voters_num,
      MAX(timestamp) AS feed_updated_at
    FROM hafbe_views.voters_stats_view
    GROUP BY witness_id
  ) vsv;

  RAISE NOTICE 'Updated witnesses cache';

  TRUNCATE TABLE hafbe_app.witness_voters_stats_change_cache;

  INSERT INTO hafbe_app.witness_voters_stats_change_cache (witness_id, voter_id, vests, account_vests, proxied_vests, approve, timestamp)
  SELECT witness_id, voter_id, vests, account_vests, proxied_vests, approve, timestamp
  FROM hafbe_views.voters_stats_change_view  
  WHERE timestamp >= 'today'::DATE;

  RAISE NOTICE 'Updated witness voters change cache';

  TRUNCATE TABLE hafbe_app.witness_votes_change_cache;

  INSERT INTO hafbe_app.witness_votes_change_cache (witness_id, votes_daily_change, voters_num_daily_change)
  SELECT
    witness_id,
    SUM(CASE WHEN approve THEN vests ELSE -1 * vests END)::BIGINT,
    SUM(CASE WHEN approve THEN 1 ELSE -1 END)::INT
  FROM hafbe_views.voters_stats_change_view
  WHERE timestamp >= 'today'::DATE
  GROUP BY witness_id;

  RAISE NOTICE 'Updated witness change cache';

  UPDATE hafbe_app.witnesses_cache_config SET last_updated_at = NOW();
END
$function$
LANGUAGE 'plpgsql'
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
;
