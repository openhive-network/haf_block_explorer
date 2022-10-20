CREATE SCHEMA IF NOT EXISTS hafbe_app AUTHORIZATION hafbe_owner;

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
    last_reported_block INT
  );
  INSERT INTO hafbe_app.app_status (continue_processing, last_processed_block, started_processing_at, last_reported_at, last_reported_block)
  VALUES (TRUE, 0, NULL, to_timestamp(0), 0);

  CREATE TABLE IF NOT EXISTS hafbe_app.witness_votes_history (
    witness_id INT NOT NULL,
    voter_id INT NOT NULL,
    approve BOOLEAN NOT NULL,
    timestamp TIMESTAMP NOT NULL
  ) INHERITS (hive.hafbe_app);

  CREATE TABLE IF NOT EXISTS hafbe_app.current_witness_votes (
    witness_id INT NOT NULL,
    voter_id INT NOT NULL,
    timestamp TIMESTAMP NOT NULL,

    CONSTRAINT pk_current_witness_votes PRIMARY KEY (witness_id, voter_id)
  ) INHERITS (hive.hafbe_app);

  CREATE TABLE IF NOT EXISTS hafbe_app.current_witnesses (
    witness_id INT NOT NULL,
    url TEXT,
    price_feed FLOAT,
    bias NUMERIC,
    feed_age INTERVAL,
    block_size INT,
    signing_key TEXT,
    version TEXT,

    CONSTRAINT pk_current_witnesses PRIMARY KEY (witness_id)
  ) INHERITS (hive.hafbe_app);

  CREATE TABLE IF NOT EXISTS hafbe_app.account_proxies_history (
    account_id INT NOT NULL,
    proxy_id INT NOT NULL,
    proxy BOOLEAN NOT NULL,
    timestamp TIMESTAMP NOT NULL
  ) INHERITS (hive.hafbe_app);

  CREATE TABLE IF NOT EXISTS hafbe_app.current_account_proxies (
    account_id INT NOT NULL,
    proxy_id INT NOT NULL,
    operation_id BIGINT NOT NULL,

    CONSTRAINT pk_current_account_proxies PRIMARY KEY (account_id)
  ) INHERITS (hive.hafbe_app);

  CREATE INDEX IF NOT EXISTS current_account_proxies_proxy_id_operation_id ON hafbe_app.current_account_proxies USING btree (proxy_id, operation_id);

  CREATE TABLE IF NOT EXISTS hafbe_app.recursive_account_proxies (
    proxy_id INT NOT NULL,
    account_id INT NOT NULL,

    CONSTRAINT pk_recursive_account_proxies PRIMARY KEY (proxy_id, account_id)
  ) INHERITS (hive.hafbe_app);

  CREATE TABLE IF NOT EXISTS hafbe_app.hived_account_cache (
    account TEXT NOT NULL,
    data JSON NOT NULL,

    CONSTRAINT pk_hived_account_cache PRIMARY KEY (account)
  );

  CREATE TABLE IF NOT EXISTS hafbe_app.account_operation_cache (
    account_id INT NOT NULL,
    op_type_id SMALLINT NOT NULL,

    CONSTRAINT pk_account_operation_cache PRIMARY KEY (account_id, op_type_id)
  ) INHERITS (hive.hafbe_app);

  CREATE TABLE IF NOT EXISTS hafbe_app.balance_impacting_op_ids (
    op_type_ids_arr SMALLINT[] NOT NULL
  );

  INSERT INTO hafbe_app.balance_impacting_op_ids (op_type_ids_arr)
  SELECT array_agg(hot.id)
  FROM hive.operation_types hot
  JOIN (
    SELECT hive.get_balance_impacting_operations() AS name
  ) bio
  ON hot.name = bio.name;

  CREATE TABLE IF NOT EXISTS hafbe_app.account_vests (
    account_id INT NOT NULL,
    vests BIGINT NOT NULL,

    CONSTRAINT pk_account_vests PRIMARY KEY (account_id)
  ) INHERITS (hive.hafbe_app);
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


CREATE OR REPLACE FUNCTION hafbe_app.process_block_range_data_c(_from INT, _to INT)
RETURNS VOID
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __prop_op RECORD;
  __prop_value TEXT;
  __balance_change RECORD;
  __balance_impacting_ops_ids INT[] = (SELECT op_type_ids_arr FROM hafbe_app.balance_impacting_op_ids);
BEGIN
  WITH vote_or_proxy_op AS (
    SELECT
      (body::JSON)->'value' AS value,
      timestamp, op_type_id, id
    FROM hive.hafbe_app_operations_view
    WHERE op_type_id =  ANY('{12,91}') AND block_num BETWEEN _from AND _to
  ),

  select_votes_ops AS (
    SELECT hav_w.witness_id, hav_v.voter_id, approve, timestamp
    FROM (
      SELECT
        value->>'witness' AS witness,
        value->>'account' AS voter,
        (value->>'approve')::BOOLEAN AS approve,
        timestamp, id
      FROM vote_or_proxy_op
      WHERE op_type_id = 12
    ) vote_op
    JOIN LATERAL (
      SELECT id AS witness_id
      FROM hive.hafbe_app_accounts_view
      WHERE name = vote_op.witness
    ) hav_w ON TRUE
    JOIN LATERAL (
      SELECT id AS voter_id
      FROM hive.hafbe_app_accounts_view
      WHERE name = vote_op.voter
    ) hav_v ON TRUE
    ORDER BY id DESC
  ),
  
  insert_votes_history AS (
    INSERT INTO hafbe_app.witness_votes_history (witness_id, voter_id, approve, timestamp)
    SELECT witness_id, voter_id, approve, timestamp
    FROM select_votes_ops
  ),

  insert_current_votes AS (
    INSERT INTO hafbe_app.current_witness_votes (witness_id, voter_id, timestamp)
    SELECT DISTINCT ON (witness_id, voter_id)
      witness_id, voter_id, timestamp
    FROM select_votes_ops
    WHERE approve IS TRUE
    ON CONFLICT ON CONSTRAINT pk_current_witness_votes DO UPDATE SET
      timestamp = EXCLUDED.timestamp
  ),

  delete_current_votes AS (
    DELETE FROM hafbe_app.current_witness_votes cwv USING select_votes_ops svo
    WHERE svo.approve IS FALSE AND cwv.witness_id = svo.witness_id AND cwv.voter_id = svo.voter_id
  ),

  insert_witnesses_from_votes AS (
    INSERT INTO hafbe_app.current_witnesses (witness_id, url, price_feed, bias, feed_age, block_size, signing_key, version)
    SELECT witness_id, NULL, NULL, NULL, NULL, NULL, NULL, '1.25.0'
    FROM select_votes_ops
    ON CONFLICT ON CONSTRAINT pk_current_witnesses DO NOTHING
  ),

  select_proxy_ops AS (
    SELECT hav_a.account_id, hav_p.proxy_id, proxy, timestamp, id AS operation_id
    FROM (
      SELECT
        value->>'account' AS account,
        value->>'proxy' AS proxy_account,
        CASE WHEN (value->>'clear')::BOOLEAN IS TRUE THEN FALSE ELSE TRUE END AS proxy,
        timestamp, id
      FROM vote_or_proxy_op
      WHERE op_type_id = 91
    ) proxy_op
    JOIN LATERAL (
      SELECT id AS account_id
      FROM hive.hafbe_app_accounts_view
      WHERE name = proxy_op.account
    ) hav_a ON TRUE
    JOIN LATERAL (
      SELECT id AS proxy_id
      FROM hive.hafbe_app_accounts_view
      WHERE name = proxy_op.proxy_account
    ) hav_p ON TRUE
    ORDER BY proxy_op.id DESC
  ),

  insert_proxy_history AS (
    INSERT INTO hafbe_app.account_proxies_history (account_id, proxy_id, proxy, timestamp)
    SELECT account_id, proxy_id, proxy, timestamp
    FROM select_proxy_ops
  ),

  insert_current_proxies AS (
    INSERT INTO hafbe_app.current_account_proxies AS cap (account_id, proxy_id, operation_id)
    SELECT DISTINCT ON (account_id)
      account_id, proxy_id, operation_id
    FROM select_proxy_ops
    ON CONFLICT ON CONSTRAINT pk_current_account_proxies DO UPDATE SET
      proxy_id = EXCLUDED.proxy_id
    RETURNING cap.account_id, cap.proxy_id, cap.operation_id
  ),

  delete_current_proxies AS (
    DELETE FROM hafbe_app.current_account_proxies cap USING select_proxy_ops spo
    WHERE spo.proxy IS FALSE AND cap.account_id = spo.account_id
    RETURNING cap.account_id, cap.proxy_id, cap.operation_id
  ),

  proxies1 AS (
    SELECT
      prox1.proxy_id AS top_proxy_id,
      prox1.account_id, prox1.operation_id
    FROM insert_current_proxies prox1
  ),

  proxies2 AS (
    SELECT prox1.top_proxy_id, prox2.account_id, prox2.operation_id
    FROM proxies1 prox1
    JOIN LATERAL (
      SELECT proxy_id, account_id, operation_id
      FROM hafbe_app.current_account_proxies
      WHERE operation_id < prox1.operation_id AND proxy_id = prox1.account_id
    ) prox2 ON TRUE
  ),

  proxies3 AS (
    SELECT prox2.top_proxy_id, prox3.account_id, prox3.operation_id
    FROM proxies2 prox2
    JOIN LATERAL (
      SELECT proxy_id, account_id, operation_id
      FROM hafbe_app.current_account_proxies
      WHERE operation_id < prox2.operation_id AND proxy_id = prox2.account_id
    ) prox3 ON TRUE
  ),

  proxies4 AS (
    SELECT prox3.top_proxy_id, prox4.account_id, prox4.operation_id
    FROM proxies3 prox3
    JOIN LATERAL (
      SELECT proxy_id, account_id, operation_id
      FROM hafbe_app.current_account_proxies
      WHERE operation_id < prox3.operation_id AND proxy_id = prox3.account_id
    ) prox4 ON TRUE
  ),

  proxies5 AS (
    SELECT prox4.top_proxy_id, prox5.account_id
    FROM proxies4 prox4
    JOIN LATERAL (
      SELECT proxy_id, account_id, operation_id
      FROM hafbe_app.current_account_proxies
      WHERE operation_id < prox4.operation_id AND proxy_id = prox4.account_id
    ) prox5 ON TRUE
  ),

  insert_recursive_account_proxies AS (
    INSERT INTO hafbe_app.recursive_account_proxies (proxy_id, account_id)
    SELECT top_proxy_id, account_id FROM proxies1
    UNION
    SELECT top_proxy_id, account_id FROM proxies2
    UNION
    SELECT top_proxy_id, account_id FROM proxies3
    UNION
    SELECT top_proxy_id, account_id FROM proxies4
    UNION
    SELECT top_proxy_id, account_id FROM proxies5
    ON CONFLICT ON CONSTRAINT pk_recursive_account_proxies DO NOTHING
  ),

  unproxies1 AS (
    SELECT
      prox1.proxy_id AS top_proxy_id,
      prox1.account_id, prox1.operation_id
    FROM delete_current_proxies prox1
  ),

  unproxies2 AS (
    SELECT prox1.top_proxy_id, prox2.account_id, prox2.operation_id
    FROM unproxies1 prox1
    JOIN LATERAL (
      SELECT proxy_id, account_id, operation_id
      FROM hafbe_app.current_account_proxies
      WHERE operation_id < prox1.operation_id AND proxy_id = prox1.account_id
    ) prox2 ON TRUE
  ),

  unproxies3 AS (
    SELECT prox2.top_proxy_id, prox3.account_id, prox3.operation_id
    FROM unproxies2 prox2
    JOIN LATERAL (
      SELECT proxy_id, account_id, operation_id
      FROM hafbe_app.current_account_proxies
      WHERE operation_id < prox2.operation_id AND proxy_id = prox2.account_id
    ) prox3 ON TRUE
  ),

  unproxies4 AS (
    SELECT prox3.top_proxy_id, prox4.account_id, prox4.operation_id
    FROM unproxies3 prox3
    JOIN LATERAL (
      SELECT proxy_id, account_id, operation_id
      FROM hafbe_app.current_account_proxies
      WHERE operation_id < prox3.operation_id AND proxy_id = prox3.account_id
    ) prox4 ON TRUE
  ),

  unproxies5 AS (
    SELECT prox4.top_proxy_id, prox5.account_id
    FROM unproxies4 prox4
    JOIN LATERAL (
      SELECT proxy_id, account_id, operation_id
      FROM hafbe_app.current_account_proxies
      WHERE operation_id < prox4.operation_id AND proxy_id = prox4.account_id
    ) prox5 ON TRUE
  ),

  select_recursive_account_unproxies AS (
    SELECT top_proxy_id, account_id FROM unproxies1
    UNION
    SELECT top_proxy_id, account_id FROM unproxies2
    UNION
    SELECT top_proxy_id, account_id FROM unproxies3
    UNION
    SELECT top_proxy_id, account_id FROM unproxies4
    UNION
    SELECT top_proxy_id, account_id FROM unproxies5
  )

  DELETE FROM hafbe_app.recursive_account_proxies rap USING select_recursive_account_unproxies raup
  WHERE rap.proxy_id = raup.top_proxy_id AND rap.account_id = raup.account_id;

  -- add new witnesses per block range
  INSERT INTO hafbe_app.current_witnesses (witness_id, url, price_feed, bias, feed_age, block_size, signing_key, version)
  SELECT DISTINCT ON (account_id)
    account_id, NULL, NULL, NULL, NULL, NULL, NULL, '1.25.0'
  FROM hive.hafbe_app_account_operations_view
  WHERE op_type_id = ANY('{42,11,7}') AND block_num BETWEEN _from AND _to
  ON CONFLICT ON CONSTRAINT pk_current_witnesses DO NOTHING;

  -- processes witness properties per block range
  FOR __prop_op IN
    SELECT
      witness_id,
      (hov.body::JSON)->'value' AS value,
      hov.op_type_id,
      hov.timestamp
    FROM hafbe_app.current_witnesses cw
    JOIN (
      SELECT account_id, operation_id, block_num
      FROM hive.hafbe_app_account_operations_view
      WHERE op_type_id = ANY('{42,30,14,11,7}'::INT[]) AND block_num BETWEEN _from AND _to
      ORDER BY operation_id ASC
    ) haov ON haov.account_id = cw.witness_id
    JOIN (
      SELECT body, op_type_id, timestamp, id, block_num
      FROM hive.hafbe_app_operations_view 
    ) hov ON hov.id = haov.operation_id AND hov.block_num = haov.block_num
        
  LOOP
    -- parse witness url 42,11
    SELECT __prop_op.value->>'url' INTO __prop_value;

    IF __prop_value IS NULL AND __prop_op.op_type_id = 42 THEN
      SELECT prop_value FROM hive.extract_set_witness_properties(__prop_op.value->>'props') WHERE prop_name = 'url' INTO __prop_value;
    END IF;

    IF __prop_value IS NOT NULL THEN
      UPDATE hafbe_app.current_witnesses cw SET url = __prop_value WHERE witness_id = __prop_op.witness_id;
    END IF;

    -- parse witness feed_data 42,7
    SELECT __prop_op.value->'exchange_rate' INTO __prop_value;

    IF __prop_value IS NULL AND __prop_op.op_type_id = 42 THEN
      SELECT prop_value FROM hive.extract_set_witness_properties(__prop_op.value->>'props') WHERE prop_name = 'hbd_exchange_rate' INTO __prop_value;
    END IF;

    IF __prop_value IS NOT NULL THEN
      UPDATE hafbe_app.current_witnesses cw SET
        price_feed = ((__prop_value::JSON)->'base'->>'amount')::NUMERIC / ((__prop_value::JSON)->'quote'->>'amount')::NUMERIC,
        bias = (((__prop_value::JSON)->'quote'->>'amount')::NUMERIC - 1000)::NUMERIC,
        feed_age = (NOW() - __prop_op.timestamp)::INTERVAL
      WHERE witness_id = __prop_op.witness_id;
    END IF;

    -- parse witness block_size 42,30,14,11
    SELECT __prop_op.value->'props'->>'maximum_block_size' INTO __prop_value;

    IF __prop_value IS NULL AND __prop_op.op_type_id = 42 THEN
      SELECT prop_value FROM hive.extract_set_witness_properties(__prop_op.value->>'props') WHERE prop_name = 'maximum_block_size' INTO __prop_value;
    END IF;

    IF __prop_value IS NOT NULL THEN
      UPDATE hafbe_app.current_witnesses cw SET block_size = __prop_value::INT WHERE witness_id = __prop_op.witness_id;
    END IF;

    -- parse witness signing_key 42,11
    SELECT __prop_op.value->>'block_signing_key' INTO __prop_value;

    IF __prop_value IS NULL AND __prop_op.op_type_id = 42 THEN
      SELECT prop_value FROM hive.extract_set_witness_properties(__prop_op.value->>'props') WHERE prop_name = 'new_signing_key' INTO __prop_value;
    END IF;

    IF __prop_value IS NULL AND __prop_op.op_type_id = 42 THEN
      SELECT prop_value FROM hive.extract_set_witness_properties(__prop_op.value->>'props') WHERE prop_name = 'key' INTO __prop_value;
    END IF;

    IF __prop_value IS NOT NULL THEN
      UPDATE hafbe_app.current_witnesses cw SET signing_key = __prop_value WHERE witness_id = __prop_op.witness_id;
    END IF;
  END LOOP;

  INSERT INTO hafbe_app.account_operation_cache (account_id, op_type_id)
  SELECT account_id, op_type_id
  FROM hive.hafbe_app_account_operations_view
  WHERE block_num BETWEEN _from AND _to
  ON CONFLICT ON CONSTRAINT pk_account_operation_cache DO NOTHING;

  -- get impacted vests balance for block range and update account_vests
  FOR __balance_change IN
    SELECT bio.account_name AS account, bio.amount AS vests
    FROM hive.hafbe_app_operations_view hov

    JOIN LATERAL (
      SELECT account_name, amount
      FROM hive.get_impacted_balances(hov.body, hov.block_num > 905693)
      WHERE asset_symbol_nai = 37
    ) bio ON TRUE
    
    WHERE hov.op_type_id = ANY(__balance_impacting_ops_ids) AND hov.block_num BETWEEN _from AND _to
    ORDER BY hov.block_num, hov.id

    LOOP
      INSERT INTO hafbe_app.account_vests (account_id, vests)
      SELECT hav.id, __balance_change.vests
      FROM hive.hafbe_app_accounts_view hav
      WHERE hav.name = __balance_change.account

      ON CONFLICT ON CONSTRAINT pk_account_vests DO 
      UPDATE SET vests = hafbe_app.account_vests.vests + EXCLUDED.vests;
    END LOOP;

  INSERT INTO hafbe_app.account_operation_cache (account_id, op_type_id)
  SELECT account_id, op_type_id
  FROM hive.hafbe_app_account_operations_view
  WHERE block_num BETWEEN _from AND _to
  ON CONFLICT ON CONSTRAINT pk_account_operation_cache DO NOTHING;
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

    IF (NOW() - (SELECT last_reported_at FROM hafbe_app.app_status))::INTERVAL >= '5 second'::INTERVAL THEN

      RAISE NOTICE 'Last processed block %', _last_block;
      RAISE NOTICE 'Processed % blocks in 5 seconds', (SELECT _last_block - last_reported_block FROM hafbe_app.app_status);
      RAISE NOTICE 'Block processing running for % minutes
      ', ROUND((EXTRACT(epoch FROM (
          SELECT NOW() - started_processing_at FROM hafbe_app.app_status
        )) / 60)::NUMERIC, 2);
      
      UPDATE hafbe_app.app_status SET last_reported_at = NOW();
      UPDATE hafbe_app.app_status SET last_reported_block = _last_block;
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

CREATE OR REPLACE PROCEDURE hafbe_app.create_context_if_not_exists(_appContext VARCHAR)
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  IF NOT hive.app_context_exists(_appContext) THEN
    RAISE NOTICE 'Attempting to create a HAF application context...';
    PERFORM hive.app_create_context(_appContext);
    PERFORM hafbe_app.define_schema();
    COMMIT;
  END IF;
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
      -- RAISE WARNING 'Waiting for next block...';
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
