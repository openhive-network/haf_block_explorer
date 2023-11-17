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

    PERFORM hafbe_app.storeLastProcessedBlock(_last_block);

    INSERT INTO hafbe_app.sync_time_logs VALUES (b, _time);

    COMMIT;

    RAISE NOTICE 'Processed % blocks in % seconds',
    _step ,ROUND(EXTRACT(epoch FROM (SELECT NOW() - last_reported_at FROM hafbe_app.app_status LIMIT 1)), 3);
    UPDATE hafbe_app.app_status SET last_reported_at = NOW();
    
    RAISE NOTICE 'Block processing running for % minutes
    ',
    ROUND((EXTRACT(epoch FROM (SELECT NOW() - started_processing_at FROM hafbe_app.app_status LIMIT 1)) / 60)::NUMERIC, 2);

    UPDATE hafbe_app.app_status SET last_reported_block = _last_block;


    EXIT WHEN NOT hafbe_app.continueProcessing();

  END LOOP;

  IF hafbe_app.continueProcessing() AND _last_block < _to THEN
    RAISE NOTICE 'Attempting to process a block range (rest): <%, %>', b, _last_block;
    --- Supplement last part of range if anything left.
    PERFORM btracker_app.process_block_range_data_a(_last_block, _to);
    RAISE NOTICE 'btracker_app Block range a (hive, hbd, vests balances): <%, %> processed successfully.', _last_block, _to;
    PERFORM btracker_app.process_block_range_data_b(_last_block, _to);
    RAISE NOTICE 'btracker_app Block range b (delegations, rewards, savings, withdraws): <%, %> processed successfully.', _last_block, _to;
    PERFORM hafbe_app.process_block_range_data_a(_last_block, _to);
    RAISE NOTICE 'hafbe_app Block range a (witness proxy, votes): <%, %> processed successfully.', _last_block, _to;
    PERFORM hafbe_app.process_block_range_data_b(_last_block, _to);
    RAISE NOTICE 'hafbe_app Block range b (witness parameters): <%, %> processed successfully.', _last_block, _to;
    PERFORM hafbe_app.process_block_range_data_c(_last_block, _to);
    RAISE NOTICE 'hafbe_app Block range c (account parameters): <%, %> processed successfully.', _last_block, _to;
    PERFORM hive.app_state_providers_update(_last_block, _to, _appContext);
    RAISE NOTICE 'app_state_provider Block range (metadata): <%, %> processed successfully.', _last_block, _to;

    _last_block := _to;

    PERFORM hafbe_app.storeLastProcessedBlock(_last_block);

    COMMIT;
    RAISE NOTICE 'Block range: <%, %> processed successfully.', b, _last_block;
  END IF;

  RAISE NOTICE 'Attaching HAF application context at block: %.', _last_block;
  CALL hive.appproc_context_attach(ARRAY[_appContext, _appContext_btracker], _last_block);
 --- You should enable here all things previously disabled at begin of this function...



 RAISE NOTICE 'Leaving massive processing of block range: <%, %>...', _from, _to;
END
$$;

RESET ROLE;
