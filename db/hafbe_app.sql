CREATE SCHEMA IF NOT EXISTS hafbe_app;

CREATE OR REPLACE FUNCTION hafbe_app.define_schema()
RETURNS VOID
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __hardfork_one_op_id INT = 1176568;
BEGIN
  RAISE NOTICE 'Attempting to create an application schema tables...';

  CREATE TABLE IF NOT EXISTS hafbe_app.app_status (
    continue_processing BOOLEAN,
    last_processed_block INT,
    started_processing_at TIMESTAMP,
    last_reported_at TIMESTAMP,
    report_time BOOLEAN
  );
  INSERT INTO hafbe_app.app_status (continue_processing, last_processed_block, started_processing_at, last_reported_at, report_time)
  VALUES (True, 0, NULL, to_timestamp(0), TRUE);

  CREATE TABLE IF NOT EXISTS hafbe_app.hardfork_operations (
    operation_id INT NOT NULL,
    hardfork_num INT NOT NULL,

    CONSTRAINT pk_hardfork_operations PRIMARY KEY (operation_id, hardfork_num)
  );
  
  INSERT INTO hafbe_app.hardfork_operations (operation_id, hardfork_num)
  SELECT CASE WHEN (
    SELECT ((body::JSON)->'value'->>'hardfork_id')::INT
    FROM hive.operations_view
    WHERE id = __hardfork_one_op_id
  ) != 1 THEN
    (SELECT id FROM hive.operations_view WHERE op_type_id = 60 ORDER BY id LIMIT 1)
  ELSE
    __hardfork_one_op_id
  END,
  1
  ;

  CREATE TABLE IF NOT EXISTS hafbe_app.witness_votes_history (
    witness_id INT NOT NULL,
    voter_id INT NOT NULL,
    approve BOOLEAN NOT NULL,
    timestamp TIMESTAMP NOT NULL
  ) INHERITS (hive.hafbe_app);

  CREATE INDEX IF NOT EXISTS witness_votes_history_witness_id_timestamp ON hafbe_app.witness_votes_history USING btree (witness_id, timestamp);

  CREATE TABLE IF NOT EXISTS hafbe_app.current_witness_votes (
    witness_id INT NOT NULL,
    voter_id INT NOT NULL,
    approve BOOLEAN NOT NULL,
    timestamp TIMESTAMP NOT NULL,

    CONSTRAINT pk_current_witness_votes PRIMARY KEY (witness_id, voter_id)
  ) INHERITS (hive.hafbe_app);
  
  CREATE INDEX IF NOT EXISTS current_witness_votes_witness_id_approve ON hafbe_app.current_witness_votes USING btree (witness_id, approve);

  CREATE TABLE IF NOT EXISTS hafbe_app.current_witnesses (
    witness_id INT NOT NULL,
    url TEXT,
    price_feed TEXT,
    bias INT,
    feed_age INTERVAL,
    block_size INT,
    signing_key TEXT,
    version TEXT,

    CONSTRAINT pk_current_witnesses PRIMARY KEY (witness_id)
  ) INHERITS (hive.hafbe_app);

  CREATE TABLE IF NOT EXISTS hafbe_app.account_proxies_history (
    account_id INT NOT NULL,
    proxy_id INT,
    proxy BOOLEAN NOT NULL,
    timestamp TIMESTAMP NOT NULL
  ) INHERITS (hive.hafbe_app);
  
  CREATE INDEX IF NOT EXISTS account_proxies_history_timestamp ON hafbe_app.account_proxies_history USING btree (timestamp);
  CREATE INDEX IF NOT EXISTS account_proxies_history_timestamp_account_id ON hafbe_app.account_proxies_history USING btree (timestamp, account_id);
  CREATE INDEX IF NOT EXISTS account_proxies_history_timestamp_proxy_id ON hafbe_app.account_proxies_history USING btree (timestamp, proxy_id);
  CREATE INDEX IF NOT EXISTS account_proxies_history_timestamp_proxy_id_proxy ON hafbe_app.account_proxies_history USING btree (timestamp, proxy_id, proxy);
  CREATE INDEX IF NOT EXISTS account_proxies_history_account_id_proxy_id ON hafbe_app.account_proxies_history USING btree (account_id, proxy_id);

  CREATE TABLE IF NOT EXISTS hafbe_app.current_account_proxies (
    account_id INT NOT NULL,
    proxy_id INT,
    proxy BOOLEAN NOT NULL,

    CONSTRAINT pk_current_account_proxies PRIMARY KEY (account_id)
  ) INHERITS (hive.hafbe_app);
  
  CREATE INDEX IF NOT EXISTS current_account_proxies_proxy_id_proxy ON hafbe_app.current_account_proxies USING btree (proxy_id, proxy);
  CREATE INDEX IF NOT EXISTS current_account_proxies_account_id_proxy ON hafbe_app.current_account_proxies USING btree (account_id, proxy);
  CREATE INDEX IF NOT EXISTS current_account_proxies_account_id_proxy_id ON hafbe_app.current_account_proxies USING btree (account_id, proxy_id);

  CREATE TABLE IF NOT EXISTS hafbe_app.hived_account_cache (
    account TEXT NOT NULL,
    data JSON NOT NULL,

    CONSTRAINT pk_hived_account_cache PRIMARY KEY (account)
  );

  CREATE TABLE IF NOT EXISTS hafbe_app.account_operation_cache (
    account_id INT NOT NULL,
    op_type_id INT NOT NULL,

    CONSTRAINT pk_account_operation_cache PRIMARY KEY (account_id, op_type_id)
  ) INHERITS (hive.hafbe_app);

  CREATE TABLE IF NOT EXISTS hafbe_app.balance_impacting_op_ids (
    op_type_id INT NOT NULL,

    CONSTRAINT pk_balance_impacting_op_ids PRIMARY KEY(op_type_id)
  );

  INSERT INTO hafbe_app.balance_impacting_op_ids (op_type_id)
  SELECT hot.id
  FROM hive.operation_types hot
  WHERE hot.name IN (SELECT * FROM hive.get_balance_impacting_operations());

  CREATE TABLE IF NOT EXISTS hafbe_app.account_vests (
    account_id INT NOT NULL,
    vests BIGINT NOT NULL,

    CONSTRAINT pk_account_vests PRIMARY KEY (account_id)
  ) INHERITS (hive.hafbe_app);

  CREATE INDEX IF NOT EXISTS account_vests_vests ON hafbe_app.account_vests USING btree (vests);

  CALL hafbe_views.create_views();

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

CREATE OR REPLACE FUNCTION hafbe_app.get_account_id(_account TEXT)
RETURNS INT
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN id FROM hive.hafbe_app_accounts_view WHERE name = _account;
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_app.unpack_from_vector(_vector TEXT)
RETURNS TEXT
LANGUAGE 'plpgsql'
AS
$$
BEGIN 
  -- TODO: to be replaced by hive fork manager method
  RETURN _vector;
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_app.parse_witness_set_props(_op_value JSON, _attr_name TEXT)
RETURNS TEXT
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __result TEXT;
BEGIN
  SELECT INTO __result
    props->>1
  FROM (
    SELECT json_array_elements(_op_value->'props') AS props
  ) to_arr
  WHERE props->>0 = _attr_name;

  IF _attr_name = 'new_signing_key' AND __result IS NULL THEN
    SELECT INTO __result
      props->>1
    FROM (
      SELECT json_array_elements(_op_value->'props') AS props
    ) to_arr
    WHERE props->>0 = 'key';
  END IF;

  RETURN hafbe_app.unpack_from_vector(__result);
END
$$
;

CREATE OR REPLACE PROCEDURE hafbe_app.add_new_witness(_witness_id INT)
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  IF (SELECT witness_id FROM hafbe_app.current_witnesses WHERE witness_id = _witness_id) IS NULL THEN
    INSERT INTO hafbe_app.current_witnesses (witness_id, url, price_feed, bias, feed_age, block_size, signing_key, version)
    VALUES (_witness_id, NULL, NULL, NULL, NULL, NULL, NULL, '1.25.0')
    ON CONFLICT ON CONSTRAINT pk_current_witnesses DO NOTHING;
  END IF;
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_app.process_block_range_data_c(_from INT, _to INT, _report_step INT = 1000)
RETURNS VOID
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __prop_value TEXT;
  __prop_op RECORD;
  __proxy_op RECORD;
  __vote_op RECORD;
  __balance_change RECORD;
  __balance_impacting_ops INT[] = (SELECT array_agg(op_type_id) FROM hafbe_app.balance_impacting_op_ids);
BEGIN
  -- main processing loop
  FOR b IN _from .. _to
  LOOP
    FOR __prop_op IN
      SELECT
        haov.account_id AS witness_id,
        (hov.body::JSON)->'value' AS value,
        hov.op_type_id,
        hov.timestamp
      FROM hive.hafbe_app_operations_view hov
      JOIN (
        SELECT account_id, operation_id, block_num
        FROM hive.hafbe_app_account_operations_view haov
      ) haov ON hov.id = haov.operation_id AND hov.block_num = haov.block_num
      WHERE hov.block_num = b AND hov.op_type_id = ANY('{42,30,14,11,7}'::INT[])
          
    LOOP
      CALL hafbe_app.add_new_witness(__prop_op.witness_id);
      
      -- parse witness url 42,11
      IF __prop_op.op_type_id = ANY('{42,11}'::INT[]) THEN
        IF __prop_op.op_type_id = 42 THEN
          SELECT hafbe_app.parse_witness_set_props(__prop_op.value, 'url') INTO __prop_value;
        ELSE
          SELECT __prop_op.value->>'url' INTO __prop_value;
        END IF;

        IF __prop_value IS NOT NULL THEN
          UPDATE hafbe_app.current_witnesses cw SET url = __prop_value WHERE witness_id = __prop_op.witness_id;
        END IF;
      
      -- parse witness feed_data 42,7
      ELSIF __prop_op.op_type_id = ANY('{42,7}'::INT[]) THEN
        IF __prop_op.op_type_id = 42 THEN
          SELECT hafbe_app.parse_witness_set_props(__prop_op.value, 'hbd_exchange_rate') INTO __prop_value;
        ELSE
          SELECT __prop_op.value->>'exchange_rate' INTO __prop_value;
        END IF;

        IF __prop_value IS NOT NULL THEN
          UPDATE hafbe_app.current_witnesses cw SET price_feed = __prop_value WHERE witness_id = __prop_op.witness_id;
          -- (((__prop_value::JSON)->'quote'->>'amount')::INT - 1000)::INT
          UPDATE hafbe_app.current_witnesses cw SET bias = 0::INT WHERE witness_id = __prop_op.witness_id;
          UPDATE hafbe_app.current_witnesses cw SET feed_age = (NOW() - __prop_op.timestamp)::INTERVAL WHERE witness_id = __prop_op.witness_id;
        END IF;

      -- parse witness block_size 42,30,14,11
      ELSIF __prop_op.op_type_id = ANY('{42,30,14,11}'::INT[]) THEN
        IF __prop_op.op_type_id = 42 THEN
          SELECT hafbe_app.parse_witness_set_props(__prop_op.value, 'maximum_block_size') INTO __prop_value;
        ELSE
          SELECT __prop_op.value->>'maximum_block_size' INTO __prop_value;
        END IF;

        IF __prop_value IS NOT NULL THEN
          UPDATE hafbe_app.current_witnesses cw SET block_size = __prop_value::INT WHERE witness_id = __prop_op.witness_id;
        END IF;

      -- parse witness signing_key 42,11
      ELSIF __prop_op.op_type_id = ANY('{42,11}'::INT[]) THEN
        IF __prop_op.op_type_id = 42 THEN
          SELECT hafbe_app.parse_witness_set_props(__prop_op.value, 'new_signing_key') INTO __prop_value;
        ELSE
          SELECT __prop_op.value->>'block_signing_key' INTO __prop_value;
        END IF;

        IF __prop_value IS NOT NULL THEN
          UPDATE hafbe_app.current_witnesses cw SET signing_key = __prop_value WHERE witness_id = __prop_op.witness_id;
        END IF;

      END IF;
    END LOOP;

    SELECT INTO __vote_op
      hafbe_app.get_account_id((body::JSON)->'value'->>'witness') AS witness_id,
      hafbe_app.get_account_id((body::JSON)->'value'->>'account') AS voter_id,
      ((body::JSON)->'value'->>'approve')::BOOLEAN AS approve,
      timestamp
    FROM hive.hafbe_app_operations_view
    WHERE op_type_id = 12 AND block_num = b
    ORDER BY id ASC;

    IF __vote_op.witness_id IS NOT NULL THEN
      INSERT INTO hafbe_app.witness_votes_history (witness_id, voter_id, approve, timestamp)
      VALUES (__vote_op.witness_id, __vote_op.voter_id, __vote_op.approve, __vote_op.timestamp);

      INSERT INTO hafbe_app.current_witness_votes (witness_id, voter_id, approve, timestamp)
      VALUES (__vote_op.witness_id, __vote_op.voter_id, __vote_op.approve, __vote_op.timestamp)
      ON CONFLICT ON CONSTRAINT pk_current_witness_votes DO UPDATE SET
        witness_id = EXCLUDED.witness_id,
        voter_id = EXCLUDED.voter_id,
        approve = EXCLUDED.approve,
        timestamp = EXCLUDED.timestamp
      ;
    END IF;

    SELECT INTO __proxy_op
      hafbe_app.get_account_id((body::JSON)->'value'->>'account') AS account_id,
      hafbe_app.get_account_id((body::JSON)->'value'->>'proxy') AS proxy_id,
      timestamp
    FROM hive.hafbe_app_operations_view
    WHERE op_type_id = 13 AND block_num = b
    ORDER BY id ASC;

    IF __proxy_op.account_id IS NOT NULL THEN
      INSERT INTO hafbe_app.account_proxies_history (account_id, proxy_id, proxy, timestamp)
      SELECT
        __proxy_op.account_id,
        CASE WHEN __proxy_op.proxy_id IS NULL THEN (
          SELECT proxy_id
          FROM hafbe_app.account_proxies_history aph
          WHERE aph.timestamp < __proxy_op.timestamp AND aph.account_id = __proxy_op.account_id AND aph.proxy_id IS NOT NULL
          ORDER BY aph.timestamp DESC
          LIMIT 1
        ) ELSE __proxy_op.proxy_id END,
        CASE WHEN __proxy_op.proxy_id IS NULL THEN FALSE ELSE TRUE END,
        __proxy_op.timestamp
      ;

      INSERT INTO hafbe_app.current_account_proxies AS cap (account_id, proxy_id, proxy)
      VALUES (__proxy_op.account_id, __proxy_op.proxy_id, TRUE)
      ON CONFLICT ON CONSTRAINT pk_current_account_proxies DO UPDATE SET
        proxy_id = CASE WHEN __proxy_op.proxy_id IS NULL THEN cap.proxy_id ELSE EXCLUDED.proxy_id END,
        proxy = CASE WHEN __proxy_op.proxy_id IS NULL THEN FALSE ELSE TRUE END
      ;
    END IF;

    INSERT INTO hafbe_app.account_operation_cache (account_id, op_type_id)
    SELECT account_id, op_type_id
    FROM hive.hafbe_app_account_operations_view
    WHERE block_num = b
    ON CONFLICT ON CONSTRAINT pk_account_operation_cache DO NOTHING;
  END LOOP;

  -- get impacted vests balance for block range and update account_vests
  FOR __balance_change IN
    SELECT bio.account_name AS account, bio.amount AS vests
    FROM hive.hafbe_app_operations_view hov

    JOIN LATERAL (
      SELECT account_name, amount
      FROM hive.get_impacted_balances(
        hov.body,
        CASE WHEN hov.id > (
          SELECT operation_id FROM hafbe_app.hardfork_operations WHERE hardfork_num = 1
        ) THEN TRUE ELSE FALSE END
      )
      WHERE asset_symbol_nai = 37
    ) bio ON TRUE
    
    WHERE hov.op_type_id = ANY(__balance_impacting_ops) AND hov.block_num BETWEEN _from AND _to
    ORDER BY hov.block_num, hov.id

    LOOP
      INSERT INTO hafbe_app.account_vests (account_id, vests)
      SELECT hav.id, __balance_change.vests
      FROM hive.hafbe_app_accounts_view hav
      WHERE hav.name = __balance_change.account

      ON CONFLICT ON CONSTRAINT pk_account_vests DO 
      UPDATE SET vests = hafbe_app.account_vests.vests + EXCLUDED.vests;
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

    --RAISE NOTICE 'Attempting to process a block range: <%, %>', b, _last_block;

    PERFORM hafbe_app.process_block_range_data_c(b, _last_block);

    COMMIT;

    --RAISE NOTICE 'Block range: <%, %> processed successfully.', b, _last_block;

    IF (SELECT report_time FROM hafbe_app.app_status) IS TRUE AND
      (NOW() - (SELECT last_reported_at FROM hafbe_app.app_status))::INTERVAL >= '5 second'::INTERVAL THEN

      RAISE NOTICE 'Last processed block %', _last_block;
      RAISE NOTICE 'Block processing running for % minutes',
        ROUND((EXTRACT(epoch FROM (
          SELECT NOW() - started_processing_at FROM hafbe_app.app_status
        )) / 60)::NUMERIC, 2);
      
      UPDATE hafbe_app.app_status SET last_reported_at = NOW();
    END IF;

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
CREATE OR REPLACE PROCEDURE hafbe_app.main(_appContext VARCHAR, _maxBlockLimit INT = NULL)
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

  IF _maxBlockLimit IS NULL THEN
    _maxBlockLimit = 2147483647;
  END IF;

  UPDATE hafbe_app.app_status SET started_processing_at = NOW();

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
