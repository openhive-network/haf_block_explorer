/** Application entry point, which:
  - defines its data schema,
  - creates HAF application context,
  - starts application main-loop (which iterates infinitely). To stop it call `hafbe_app.stopProcessing();` from another session and commit its trasaction.
*/
CREATE OR REPLACE PROCEDURE hafbe_app.main(_appContext VARCHAR, _maxBlockLimit INT = NULL)
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __last_block INT;
  __next_block_range hive.blocks_range;
BEGIN
  PERFORM hafbe_app.allowProcessing();
  COMMIT;

  SELECT hafbe_app.lastProcessedBlock() INTO __last_block;

  RAISE NOTICE 'Last block processed by application: %', __last_block;

  IF NOT hive.app_context_is_attached(_appContext) THEN
    PERFORM hive.app_context_attach(_appContext, __last_block);
  END IF;

  RAISE NOTICE 'Entering application main loop...';

  IF _maxBlockLimit IS NULL THEN
    _maxBlockLimit = 2147483647;
  END IF;

  UPDATE hafbe_app.app_status SET started_processing_at = NOW();

  WHILE hafbe_app.continueProcessing() AND (_maxBlockLimit = 0 OR __last_block < _maxBlockLimit) LOOP
    __next_block_range := hive.app_next_block(_appContext);
    COMMIT;

    IF __next_block_range IS NULL THEN
       RAISE WARNING 'Waiting for next block...';
    ELSE
      IF _maxBlockLimit != 0 and __next_block_range.first_block > _maxBlockLimit THEN
        __next_block_range.first_block  := _maxBlockLimit;
      END IF;

      IF _maxBlockLimit != 0 and __next_block_range.last_block > _maxBlockLimit THEN
        __next_block_range.last_block  := _maxBlockLimit;
      END IF;

      RAISE NOTICE 'Attempting to process block range: <%,%>', __next_block_range.first_block, __next_block_range.last_block;

      IF __next_block_range.first_block != __next_block_range.last_block THEN
        CALL hafbe_app.do_massive_processing(_appContext, _btrackerContext, __next_block_range.first_block, __next_block_range.last_block, 100, __last_block);
      ELSE
        CALL hafbe_app.processBlock(__next_block_range.last_block);
        __last_block := __next_block_range.last_block;
      END IF;

      IF __next_block_range.first_block = __next_block_range.last_block AND 
      (SELECT finished_processing_at FROM hafbe_app.app_status LIMIT 1) IS NULL THEN
      UPDATE hafbe_app.app_status SET finished_processing_at = NOW();
        PERFORM hafbe_indexes.create_hafbe_indexes();
        PERFORM btracker_app.create_btracker_indexes();
      END IF;

      IF __next_block_range.first_block = __next_block_range.last_block AND
      (NOW() - (SELECT last_updated_at FROM hafbe_app.witnesses_cache_config LIMIT 1)) >= 
      (SELECT update_interval FROM hafbe_app.witnesses_cache_config LIMIT 1) THEN
        CALL hafbe_app.update_witnesses_cache();
      END IF;

  END IF;

  END LOOP;

  RAISE NOTICE 'Exiting application main loop at processed block: %.', __last_block;
  PERFORM hafbe_app.storeLastProcessedBlock(__last_block);

  COMMIT;
END
$$
;