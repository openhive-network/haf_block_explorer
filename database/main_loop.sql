SET ROLE hafbe_owner;

/** Application entry point, which:
  - defines its data schema,
  - creates HAF application context,
  - starts application main-loop (which iterates infinitely).
    To stop it call `hafbe_app.stopProcessing();` from another session and commit its trasaction.
*/
CREATE OR REPLACE PROCEDURE hafbe_app.main(
    IN _appContext hive.context_name,
    IN _appContext_btracker hive.context_name,
    IN _appContext_reptracker hive.context_name,
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
      ARRAY[_appContext, _appContext_btracker, _appContext_reptracker],
      _blocks_range, 
      _override_max_batch => NULL, 
      _limit => _maxBlockLimit);

    IF NOT hafbe_app.continueProcessing() THEN
      ROLLBACK;
      RETURN;
    END IF;

    IF _blocks_range IS NULL THEN
      RAISE WARNING 'Waiting for next block...';
      CONTINUE;
    END IF;

    PERFORM hafbe_app.log_and_process_blocks(_appContext, _appContext_btracker, _appContext_reptracker, _blocks_range);
  END LOOP;

  RAISE NOTICE 'Exiting application main loop at processed block: %.', hive.app_get_current_block_num(_appContext);
END
$$;


RESET ROLE;
