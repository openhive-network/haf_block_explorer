CREATE SCHEMA IF NOT EXISTS hafbe_app;

CREATE OR REPLACE FUNCTION hafbe_app.define_schema()
RETURNS VOID
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RAISE NOTICE 'Attempting to create an application schema tables...';

  CREATE TABLE IF NOT EXISTS hafbe_app.app_status (
    continue_processing BOOLEAN,
    last_processed_block INT
  );
  INSERT INTO hafbe_app.app_status (continue_processing, last_processed_block)
  VALUES (True, 0);

  CREATE TABLE IF NOT EXISTS hafbe_app.witness_votes (
    witness_id INT NOT NULL,
    voter_id INT NOT NULL,
    approve BOOLEAN NOT NULL,
    operation_id BIGINT NOT NULL
  ) INHERITS (hive.hafbe_app);

  CREATE INDEX IF NOT EXISTS witness_votes_witness_id ON hafbe_app.witness_votes USING btree (witness_id);
  CREATE INDEX IF NOT EXISTS witness_votes_voter_id ON hafbe_app.witness_votes USING btree (voter_id);
  CREATE INDEX IF NOT EXISTS witness_votes_operation_id ON hafbe_app.witness_votes USING btree (operation_id);

  CREATE TABLE IF NOT EXISTS hafbe_app.account_proxies (
    account_id INT NOT NULL,
    proxy_id INT,
    proxy BOOLEAN,
    operation_id BIGINT NOT NULL
  ) INHERITS (hive.hafbe_app);

  CREATE INDEX IF NOT EXISTS account_proxies_account_id ON hafbe_app.account_proxies USING btree (account_id);
  CREATE INDEX IF NOT EXISTS account_proxies_proxy_id ON hafbe_app.account_proxies USING btree (proxy_id);
  CREATE INDEX IF NOT EXISTS account_proxies_operation_id ON hafbe_app.account_proxies USING btree (operation_id);

  CREATE TABLE IF NOT EXISTS hafbe_app.hived_account_cache (
    account TEXT NOT NULL,
    data JSON NOT NULL,

    CONSTRAINT pk_hived_account_cache PRIMARY KEY (account)
  );

  CREATE TABLE IF NOT EXISTS hafbe_app.account_operation_cache (
    uq_key TEXT NOT NULL,
    account_id INT NOT NULL,
    op_type_id INT NOT NULL,

    CONSTRAINT uq_account_operation_cache UNIQUE (uq_key)
  ) INHERITS (hive.hafbe_app);

  CREATE INDEX IF NOT EXISTS account_operation_cache_account_id ON hafbe_app.account_operation_cache USING btree (account_id);
  CREATE INDEX IF NOT EXISTS account_operation_cache_op_type_id ON hafbe_app.account_operation_cache USING btree (op_type_id);

  --ALTER SCHEMA hafbe_app OWNER TO hafbe_owner;
END
$$
;

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

CREATE FUNCTION hafbe_app.get_account_id(_account TEXT)
RETURNS INT
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN id FROM hive.accounts_view WHERE name = _account;
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_app.process_block_range_data_c(_from INT, _to INT, _report_step INT = 1000)
RETURNS VOID
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __last_reported_block INT := 0;
  __unproxy_op RECORD;
  __last_op_id BIGINT;
BEGIN
  FOR b IN _from .. _to
  LOOP

    INSERT INTO hafbe_app.witness_votes (witness_id, voter_id, approve, operation_id)
    SELECT
      hafbe_app.get_account_id(approve_operation->>'witness'),
      hafbe_app.get_account_id(approve_operation->>'account'),
      (approve_operation->>'approve')::BOOLEAN,
      id
    FROM (
      SELECT
        (body::JSON)->'value' AS approve_operation,
        id
      FROM hive.operations_view
      WHERE op_type_id = 12 AND block_num = b
    ) hov
    ON CONFLICT DO NOTHING;

    SELECT operation_id FROM hafbe_app.account_proxies ORDER BY operation_id DESC LIMIT 1 INTO __last_op_id;
    
    INSERT INTO hafbe_app.account_proxies (account_id, proxy_id, proxy, operation_id)
    SELECT
      account_id,
      proxy_id,
      CASE WHEN proxy_id IS NULL THEN FALSE ELSE TRUE END,
      id
    FROM (
      SELECT
        hafbe_app.get_account_id(proxy_operation->>'account') AS account_id,
        hafbe_app.get_account_id(proxy_operation->>'proxy') AS proxy_id,
        id
      FROM (
        SELECT
          (body::JSON)->'value' AS proxy_operation,
          id
        FROM hive.operations_view
        WHERE op_type_id = 13 AND block_num = b
      ) hov
    ) acc_ids
    ON CONFLICT DO NOTHING;

    -- postprocessing to fill null values of proxy_id when account does unproxy
    FOR __unproxy_op IN
      SELECT account_id, operation_id
      FROM hafbe_app.account_proxies
      WHERE operation_id > __last_op_id AND proxy_id IS NULL
    LOOP
      UPDATE hafbe_app.account_proxies
      SET proxy_id = (SELECT proxy_id
      FROM hafbe_app.account_proxies
      WHERE operation_id < __unproxy_op.operation_id AND account_id = __unproxy_op.account_id AND proxy_id IS NOT NULL
      ORDER BY operation_id DESC
      LIMIT 1)
      WHERE account_id = __unproxy_op.account_id AND proxy_id IS NULL;
    END LOOP;


    INSERT INTO hafbe_app.account_operation_cache (uq_key, account_id, op_type_id)
    SELECT
      account_id::TEXT || '-' || op_type_id::TEXT,
      account_id,
      op_type_id
    FROM hive.account_operations_view haov
    WHERE block_num = b
    ON CONFLICT DO NOTHING;
    
    /*
    IF __balance_change.source_op_block % _report_step = 0 AND __last_reported_block != __balance_change.source_op_block THEN
      RAISE NOTICE 'Processed data for block: %', __balance_change.source_op_block;
      __last_reported_block := __balance_change.source_op_block;
    END IF;
    */
  END LOOP;
END
$$
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
;

CREATE OR REPLACE PROCEDURE hafbe_app.do_massive_processing(IN _appContext VARCHAR, IN _from INT, IN _to INT, IN _step INT, INOUT _last_block INT)
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RAISE NOTICE 'Entering massive processing of block range: <%, %>...', _from, _to;
  RAISE NOTICE 'Detaching HAF application context...';
  PERFORM hive.app_context_detach(_appContext);

  --- You can do here also other things to speedup your app, i.e. disable constrains, remove indexes etc.

  FOR b IN _from .. _to BY _step LOOP
    _last_block := b + _step - 1;

    IF _last_block > _to THEN --- in case the _step is larger than range length
      _last_block := _to;
    END IF;

    RAISE NOTICE 'Attempting to process a block range: <%, %>', b, _last_block;

    PERFORM hafbe_app.process_block_range_data_c(b, _last_block);

    COMMIT;

    RAISE NOTICE 'Block range: <%, %> processed successfully.', b, _last_block;

    EXIT WHEN NOT hafbe_app.continueProcessing();

  END LOOP;

  IF hafbe_app.continueProcessing() AND _last_block < _to THEN
    RAISE NOTICE 'Attempting to process a block range (rest): <%, %>', b, _last_block;
    --- Supplement last part of range if anything left.
    PERFORM hafbe_app.process_block_range_data_c(_last_block, _to);
    _last_block := _to;

    COMMIT;
    RAISE NOTICE 'Block range: <%, %> processed successfully.', b, _last_block;
  END IF;

  RAISE NOTICE 'Attaching HAF application context at block: %.', _last_block;
  PERFORM hive.app_context_attach(_appContext, _last_block);

 --- You should enable here all things previously disabled at begin of this function...

 RAISE NOTICE 'Leaving massive processing of block range: <%, %>...', _from, _to;
END
$$
;

CREATE OR REPLACE PROCEDURE hafbe_app.processBlock(_block INT)
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  PERFORM hafbe_app.process_block_range_data_c(_block, _block);
  COMMIT; -- For single block processing we want to commit all changes for each one.
END
$$
;

/** Application entry point, which:
  - defines its data schema,
  - creates HAF application context,
  - starts application main-loop (which iterates infinitely). To stop it call `hafbe_app.stopProcessing();` from another session and commit its trasaction.
*/
CREATE OR REPLACE PROCEDURE hafbe_app.main(_appContext VARCHAR, _maxBlockLimit INT = 0)
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __last_block INT;
  __next_block_range hive.blocks_range;
BEGIN
  IF NOT hive.app_context_exists(_appContext) THEN
    RAISE NOTICE 'Attempting to create a HAF application context...';
    PERFORM hive.app_create_context(_appContext);
    PERFORM hafbe_app.define_schema();
    COMMIT;
  END IF;

  PERFORM hafbe_app.allowProcessing();
  COMMIT;

  SELECT hafbe_app.lastProcessedBlock() INTO __last_block;

  RAISE NOTICE 'Last block processed by application: %', __last_block;

  IF NOT hive.app_context_is_attached(_appContext) THEN
    PERFORM hive.app_context_attach(_appContext, __last_block);
  END IF;

  RAISE NOTICE 'Entering application main loop...';

  WHILE hafbe_app.continueProcessing() AND (_maxBlockLimit = 0 OR __last_block < _maxBlockLimit) LOOP
    __next_block_range := hive.app_next_block(_appContext);

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
        CALL hafbe_app.do_massive_processing(_appContext, __next_block_range.first_block, __next_block_range.last_block, 100, __last_block);
      ELSE
        CALL hafbe_app.processBlock(__next_block_range.last_block);
        __last_block := __next_block_range.last_block;
      END IF;

    END IF;

  END LOOP;

  RAISE NOTICE 'Exiting application main loop at processed block: %.', __last_block;
  PERFORM hafbe_app.storeLastProcessedBlock(__last_block);

  COMMIT;
END
$$
;
