
SELECT hive.app_create_context('keyauth_live');

CREATE TABLE IF NOT EXISTS keyauth_live.app_status
(
  continue_processing BOOLEAN NOT NULL,
  last_processed_block INT NOT NULL
);

INSERT INTO keyauth_live.app_status
(continue_processing, last_processed_block)
VALUES
(True, 0)
;

CREATE OR REPLACE FUNCTION keyauth_live.continueProcessing()
RETURNS BOOLEAN
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN continue_processing FROM keyauth_live.app_status LIMIT 1;
END
$$;

CREATE OR REPLACE FUNCTION keyauth_live.allowProcessing()
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
  UPDATE keyauth_live.app_status SET continue_processing = True;
END
$$;

/** Helper function to be called from separate transaction (must be committed)
    to safely stop execution of the application.
**/
CREATE OR REPLACE FUNCTION keyauth_live.stopProcessing()
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
  UPDATE keyauth_live.app_status SET continue_processing = False;
END
$$;

CREATE OR REPLACE FUNCTION keyauth_live.storeLastProcessedBlock(
    IN _lastBlock INT
)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
  UPDATE keyauth_live.app_status SET last_processed_block = _lastBlock;
END
$$;

CREATE OR REPLACE FUNCTION keyauth_live.lastProcessedBlock()
RETURNS INT
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN last_processed_block FROM keyauth_live.app_status LIMIT 1;
END
$$;

CREATE OR REPLACE PROCEDURE keyauth_live.processBlock(IN _block INT)
LANGUAGE 'plpgsql'
AS
$$
BEGIN
    PERFORM hive.app_state_providers_update(_block, _block, 'keyauth_live');

  COMMIT; -- For single block processing we want to commit all changes for each one.
END
$$;


CREATE OR REPLACE PROCEDURE keyauth_live.do_massive_processing(
    IN _appContext VARCHAR,
    IN _from INT,
    IN _to INT,
    IN _step INT,
    INOUT _last_block INT
)
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RAISE NOTICE 'Entering massive processing of block range: <%, %>...', _from, _to;
  RAISE NOTICE 'Detaching HAF application context...';
  CALL hive.appproc_context_detach(_appContext);

  --- You can do here also other things to speedup your app, i.e. disable constrains, remove indexes etc.

  FOR b IN _from .. _to BY _step LOOP
    _last_block := b + _step - 1;

    IF _last_block > _to THEN --- in case the _step is larger than range length
      _last_block := _to;
    END IF;

    RAISE NOTICE 'Attempting to process a block range: <%, %>', b, _last_block;

    PERFORM hive.app_state_providers_update(b, _last_block, _appContext);

    PERFORM keyauth_live.storeLastProcessedBlock(_last_block);

    COMMIT;

    RAISE NOTICE 'Block range: <%, %> processed successfully.', b, _last_block;

    EXIT WHEN NOT keyauth_live.continueProcessing();

  END LOOP;

  IF keyauth_live.continueProcessing() AND _last_block < _to THEN
    RAISE NOTICE 'Attempting to process a block range (rest): <%, %>', b, _last_block;
    --- Supplement last part of range if anything left.
    PERFORM hive.app_state_providers_update(b, _last_block, _appContext);

    _last_block := _to;

    PERFORM keyauth_live.storeLastProcessedBlock(_last_block);

    COMMIT;
    RAISE NOTICE 'Block range: <%, %> processed successfully.', b, _last_block;
  END IF;

  RAISE NOTICE 'Attaching HAF application context at block: %.', _last_block;
  CALL hive.appproc_context_attach(_appContext, _last_block);

 --- You should enable here all things previously disabled at begin of this function...

 RAISE NOTICE 'Leaving massive processing of block range: <%, %>...', _from, _to;
END
$$;


CREATE OR REPLACE PROCEDURE keyauth_live.main(
    IN _appContext VARCHAR, IN _maxBlockLimit INT = 0
)
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __last_block INT;
  __next_block_range hive.blocks_range;

BEGIN
  PERFORM keyauth_live.allowProcessing();
  COMMIT;

  SELECT keyauth_live.lastProcessedBlock() INTO __last_block;

  RAISE NOTICE 'Last block processed by application: %', __last_block;

  IF NOT hive.app_context_is_attached(_appContext) THEN
    CALL hive.appproc_context_attach(_appContext, __last_block);
  END IF;

  RAISE NOTICE 'Entering application main loop...';

  WHILE keyauth_live.continueProcessing() AND (_maxBlockLimit = 0 OR __last_block < _maxBlockLimit) LOOP
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
        CALL keyauth_live.do_massive_processing(_appContext, __next_block_range.first_block, __next_block_range.last_block, 10000, __last_block);
      ELSE
        CALL keyauth_live.processBlock(__next_block_range.last_block);
        __last_block := __next_block_range.last_block;
      END IF;

    END IF;

  END LOOP;

  RAISE NOTICE 'Exiting application main loop at processed block: %.', __last_block;
  PERFORM keyauth_live.storeLastProcessedBlock(__last_block);

  COMMIT;
END
$$;
