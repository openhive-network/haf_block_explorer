SET ROLE hafbe_owner;

CREATE OR REPLACE PROCEDURE hafbe_app.do_massive_processing(
    IN _appContext VARCHAR,
    IN _appContext_btracker VARCHAR,
    IN _from INT,
    IN _to INT,
    IN _step INT,
    INOUT _last_block INT
)
LANGUAGE 'plpgsql'
AS
$$
DECLARE
_time JSONB = '{}'::JSONB;
BEGIN
  RAISE NOTICE 'Entering massive processing of block range: <%, %>...', _from, _to;
  RAISE NOTICE 'Detaching HAF application context...';
  CALL hive.appproc_context_detach(ARRAY[_appContext, _appContext_btracker]);
  --- You can do here also other things to speedup your app, i.e. disable constrains, remove indexes etc.

  FOR b IN _from .. _to BY _step LOOP
    _last_block := b + _step - 1;

    IF _last_block > _to THEN --- in case the _step is larger than range length
      _last_block := _to;
    END IF;

    RAISE NOTICE 'Attempting to process a block range: <%, %>', b, _last_block;

    SELECT hafbe_backend.get_sync_time(_time, 'time_on_start') INTO _time;
    PERFORM btracker_app.process_block_range_data_a(b, _last_block);
    SELECT hafbe_backend.get_sync_time(_time, 'btracker_app_a') INTO _time;

    SELECT hafbe_backend.get_sync_time(_time, 'time_on_start') INTO _time;
    PERFORM btracker_app.process_block_range_data_b(b, _last_block);
    SELECT hafbe_backend.get_sync_time(_time, 'btracker_app_b') INTO _time;

    SELECT hafbe_backend.get_sync_time(_time, 'time_on_start') INTO _time;
    PERFORM hafbe_app.process_block_range_data_a(b, _last_block);
    SELECT hafbe_backend.get_sync_time(_time, 'hafbe_app_a') INTO _time;

    SELECT hafbe_backend.get_sync_time(_time, 'time_on_start') INTO _time;
    PERFORM hafbe_app.process_block_range_data_b(b, _last_block);
    SELECT hafbe_backend.get_sync_time(_time, 'hafbe_app_b') INTO _time;

    SELECT hafbe_backend.get_sync_time(_time, 'time_on_start') INTO _time;
    PERFORM hafbe_app.process_block_range_data_c(b, _last_block);
    SELECT hafbe_backend.get_sync_time(_time, 'hafbe_app_c') INTO _time;

    SELECT hafbe_backend.get_sync_time(_time, 'time_on_start') INTO _time;
    PERFORM hive.app_state_providers_update(b, _last_block, _appContext);
    SELECT hafbe_backend.get_sync_time(_time, 'state_provider') INTO _time;

    INSERT INTO hafbe_app.sync_time_logs (block_num, time_json) VALUES (b, _time);

    RAISE NOTICE 'Processed % blocks in % seconds',
    _step ,ROUND(EXTRACT(epoch FROM (SELECT NOW() - last_reported_at FROM hafbe_app.app_status LIMIT 1)), 3);
    UPDATE hafbe_app.app_status SET last_reported_at = NOW();
    
    RAISE NOTICE 'Block processing running for % minutes
    ',
    ROUND((EXTRACT(epoch FROM (SELECT NOW() - started_processing_at FROM hafbe_app.app_status LIMIT 1)) / 60)::NUMERIC, 2);

    --Save off last processed block number from the batch of blocks (current block number is directly managed during massive sync)
    PERFORM hive.app_set_current_block_num(ARRAY[_appContext, _appContext_btracker], _last_block);
    
    COMMIT; --only commit after all block processing is finished for a batch of blocks

    EXIT WHEN NOT hafbe_app.continueProcessing();

  END LOOP;

  RAISE NOTICE 'Attaching HAF application context at block: %.', _last_block;
  CALL hive.appproc_context_attach(ARRAY[_appContext, _appContext_btracker], _last_block);
 --- You should enable here all things previously disabled at begin of this function...

 RAISE NOTICE 'Leaving massive processing of block range: <%, %>...', _from, _to;
END
$$;

RESET ROLE;
