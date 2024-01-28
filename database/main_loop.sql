SET ROLE hafbe_owner;

/** Application entry point, which:
  - defines its data schema,
  - creates HAF application context,
  - starts application main-loop (which iterates infinitely).
    To stop it call `hafbe_app.stopProcessing();` from another session and commit its trasaction.
*/
CREATE OR REPLACE PROCEDURE hafbe_app.main(_appContext VARCHAR, _appContext_btracker VARCHAR, _maxBlockLimit INT = NULL)
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __last_block INT;
  __next_block_range hive.blocks_range;
  __block_range_len INT := 0;
  __massive_processing_threshold INT := 100;
  __original_commit_mode TEXT;
  __commit_mode_changed BOOLEAN := false;

BEGIN
  PERFORM hafbe_app.allowProcessing();

  SELECT current_setting('synchronous_commit') into __original_commit_mode;

  SELECT hive.get_current_block_num() INTO __last_block;
  RAISE NOTICE 'Last block processed by application: %', __last_block;

  IF NOT hive.app_context_are_attached(ARRAY[_appContext, _appContext_btracker]) THEN
    CALL hive.appproc_context_attach(ARRAY[_appContext, _appContext_btracker], __last_block);
  END IF;

  RAISE NOTICE 'Entering application main loop...';

  IF _maxBlockLimit IS NULL THEN
    _maxBlockLimit = 2147483647;
  END IF;

  UPDATE hafbe_app.app_status SET started_processing_at = NOW();
  COMMIT; --save startup state of app

  WHILE hafbe_app.continueProcessing() AND (_maxBlockLimit = 0 OR __last_block < _maxBlockLimit) LOOP
    __next_block_range := hive.app_next_block(ARRAY[_appContext, _appContext_btracker]);

    IF __next_block_range IS NOT NULL THEN
    
      IF _maxBlockLimit != 0 and __next_block_range.first_block > _maxBlockLimit THEN
        __next_block_range.first_block  := _maxBlockLimit;
      END IF;

      IF _maxBlockLimit != 0 and __next_block_range.last_block > _maxBlockLimit THEN
        __next_block_range.last_block  := _maxBlockLimit;
      END IF;

      RAISE NOTICE 'Attempting to process block range: <%,%>', __next_block_range.first_block, __next_block_range.last_block;

      __block_range_len := __next_block_range.last_block - __next_block_range.first_block + 1;

      IF __block_range_len >= __massive_processing_threshold THEN
        IF NOT __commit_mode_changed AND __original_commit_mode != 'OFF' THEN
          PERFORM set_config('synchronous_commit', 'OFF', false);
          __commit_mode_changed := true;
        END IF;
        CALL hafbe_app.do_massive_processing(_appContext, _appContext_btracker, __next_block_range.first_block, __next_block_range.last_block, 10000, __last_block);
      ELSE
        IF __commit_mode_changed THEN
          PERFORM set_config('synchronous_commit', __original_commit_mode, false);
          __commit_mode_changed := false;
        END IF;
        FOR __block IN __next_block_range.first_block .. __next_block_range.last_block LOOP
          CALL hafbe_app.processBlock(__block, _appContext);
          __last_block := __block;
          EXIT WHEN hafbe_app.continueProcessing() OR (_maxBlockLimit != 0 AND __last_block >= _maxBlockLimit);
        END LOOP;

        IF (NOW() - (SELECT last_updated_at FROM hafbe_app.witnesses_cache_config LIMIT 1)) >= 
           (SELECT update_interval FROM hafbe_app.witnesses_cache_config LIMIT 1) THEN
          RAISE NOTICE 'Process witness cache...';
          CALL hafbe_app.update_witnesses_cache();
          RAISE NOTICE 'Witness cache processing done.';
        END IF;
      END IF;

      IF __next_block_range.first_block = __next_block_range.last_block AND 
         (SELECT finished_processing_at FROM hafbe_app.app_status LIMIT 1) IS NULL THEN
        UPDATE hafbe_app.app_status SET finished_processing_at = NOW();
        PERFORM hafbe_indexes.create_hafbe_indexes();
        PERFORM hafbe_indexes.create_btracker_indexes();
      END IF;

    END IF;
    COMMIT; --only commit after we've returned to a consistent state
  END LOOP;

  RAISE NOTICE 'Exiting application main loop at processed block: %.', __last_block;
END
$$;

RESET ROLE;
