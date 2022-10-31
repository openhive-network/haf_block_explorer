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

    CONSTRAINT pk_current_account_proxies PRIMARY KEY (account_id)
  ) INHERITS (hive.hafbe_app);

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

  CREATE TABLE IF NOT EXISTS hafbe_app.balance_impacting_op_ids (
    op_type_ids_arr SMALLINT[] NOT NULL
  );

  INSERT INTO hafbe_app.balance_impacting_op_ids (op_type_ids_arr)
  SELECT array_agg(hot.id)
  FROM hive.operation_types hot
  JOIN (
    SELECT get_balance_impacting_operations AS name
    FROM hive.get_balance_impacting_operations()
  ) bio ON bio.name = hot.name::TEXT;

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
  __vote_or_proxy_op RECORD;
  __prop_op RECORD;
  __balance_change RECORD;
  __balance_impacting_ops_ids INT[] = (SELECT op_type_ids_arr FROM hafbe_app.balance_impacting_op_ids);
BEGIN

  SELECT INTO __vote_or_proxy_op
    (body::JSON)->'value' AS value,
    timestamp, op_type_id, id AS operation_id
  FROM hive.hafbe_app_operations_view
  WHERE op_type_id = ANY('{12,91}') AND block_num BETWEEN _from AND _to;

  -- process vote ops
  WITH select_votes_ops AS (
    SELECT hav_w.id AS witness_id, hav_v.id AS voter_id, approve, timestamp, operation_id
    FROM (
      SELECT
        __vote_or_proxy_op.value->>'witness' AS witness,
        __vote_or_proxy_op.value->>'account' AS voter,
        (__vote_or_proxy_op.value->>'approve')::BOOLEAN AS approve,
        __vote_or_proxy_op.timestamp, __vote_or_proxy_op.operation_id
      WHERE __vote_or_proxy_op.op_type_id = 12
    ) vote_op
    JOIN hive.hafbe_app_accounts_view hav_w ON hav_w.name = vote_op.witness
    JOIN hive.hafbe_app_accounts_view hav_v ON hav_v.name = vote_op.voter
    ORDER BY operation_id DESC
  ),
  
  insert_votes_history AS (
    INSERT INTO hafbe_app.witness_votes_history (witness_id, voter_id, approve, timestamp)
    SELECT witness_id, voter_id, approve, timestamp
    FROM select_votes_ops
  ),

  select_latest_vote_ops AS (
    SELECT witness_id, voter_id, approve, timestamp
    FROM (
      SELECT
        ROW_NUMBER() OVER (PARTITION BY witness_id, voter_id ORDER BY operation_id DESC) AS row_n,
        witness_id, voter_id, approve, timestamp
      FROM select_votes_ops
    ) row_count
    WHERE row_n = 1
  ),

  insert_current_votes AS (
    INSERT INTO hafbe_app.current_witness_votes (witness_id, voter_id, timestamp)
    SELECT witness_id, voter_id, timestamp
    FROM select_latest_vote_ops
    WHERE approve IS TRUE
    ON CONFLICT ON CONSTRAINT pk_current_witness_votes DO UPDATE SET
      timestamp = EXCLUDED.timestamp
  )

  DELETE FROM hafbe_app.current_witness_votes cwv USING (
    SELECT witness_id, voter_id
    FROM select_latest_vote_ops
    WHERE approve IS FALSE
  ) svo
  WHERE cwv.witness_id = svo.witness_id AND cwv.voter_id = svo.voter_id;

  -- process proxy ops
  WITH select_proxy_ops AS (
    SELECT hav_a.id AS account_id, hav_p.id AS proxy_id, proxy, timestamp, operation_id
    FROM (
      SELECT
        __vote_or_proxy_op.value->>'account' AS account,
        __vote_or_proxy_op.value->>'proxy' AS proxy_account,
        CASE WHEN (__vote_or_proxy_op.value->>'clear')::BOOLEAN IS TRUE THEN FALSE ELSE TRUE END AS proxy,
        __vote_or_proxy_op.timestamp, __vote_or_proxy_op.operation_id
      WHERE __vote_or_proxy_op.op_type_id = 91
    ) proxy_op
    JOIN hive.hafbe_app_accounts_view hav_a ON hav_a.name = proxy_op.account
    JOIN hive.hafbe_app_accounts_view hav_p ON hav_p.name = proxy_op.proxy_account
    ORDER BY operation_id DESC
  ),

  insert_proxy_history AS (
    INSERT INTO hafbe_app.account_proxies_history (account_id, proxy_id, proxy, timestamp)
    SELECT account_id, proxy_id, proxy, timestamp
    FROM select_proxy_ops
  ),

  select_latest_proxy_ops AS (
    SELECT account_id, proxy_id, proxy, timestamp
    FROM (
      SELECT
        ROW_NUMBER() OVER (PARTITION BY account_id, proxy_id ORDER BY operation_id DESC) AS row_n,
        account_id, proxy_id, proxy, timestamp
      FROM select_proxy_ops
    ) row_count
    WHERE row_n = 1
  ),

  insert_current_proxies AS (
    INSERT INTO hafbe_app.current_account_proxies AS cap (account_id, proxy_id)
    SELECT account_id, proxy_id
    FROM select_latest_proxy_ops
    WHERE proxy IS TRUE

    ON CONFLICT ON CONSTRAINT pk_current_account_proxies DO UPDATE SET
      proxy_id = EXCLUDED.proxy_id
    RETURNING cap.account_id, cap.proxy_id
  ),

  delete_current_proxies AS (
    DELETE FROM hafbe_app.current_account_proxies cap USING (
      SELECT account_id
      FROM select_latest_proxy_ops
      WHERE proxy IS FALSE
    ) spo
    WHERE cap.account_id = spo.account_id
    RETURNING cap.account_id, cap.proxy_id
  ),

  unproxies1 AS (
    SELECT
      prox1.proxy_id AS top_proxy_id,
      prox1.account_id
    FROM delete_current_proxies prox1
  ),

  unproxies2 AS (
    SELECT prox1.top_proxy_id, prox2.account_id
    FROM unproxies1 prox1
    JOIN hafbe_app.current_account_proxies prox2 ON prox2.proxy_id = prox1.account_id
  ),

  unproxies3 AS (
    SELECT prox2.top_proxy_id, prox3.account_id
    FROM unproxies2 prox2
    JOIN hafbe_app.current_account_proxies prox3 ON prox3.proxy_id = prox2.account_id
  ),

  unproxies4 AS (
    SELECT prox3.top_proxy_id, prox4.account_id
    FROM unproxies3 prox3
    JOIN hafbe_app.current_account_proxies prox4 ON prox4.proxy_id = prox3.account_id
  ),

  unproxies5 AS (
    SELECT prox4.top_proxy_id, prox5.account_id
    FROM unproxies4 prox4
    JOIN hafbe_app.current_account_proxies prox5 ON prox5.proxy_id = prox4.account_id
  ),

  delete_recursive_account_unproxies AS (
    DELETE FROM hafbe_app.recursive_account_proxies rap USING (
      SELECT top_proxy_id, account_id FROM unproxies1
      UNION
      SELECT top_proxy_id, account_id FROM unproxies2
      UNION
      SELECT top_proxy_id, account_id FROM unproxies3
      UNION
      SELECT top_proxy_id, account_id FROM unproxies4
      UNION
      SELECT top_proxy_id, account_id FROM unproxies5
    ) raup
    WHERE rap.proxy_id = raup.top_proxy_id AND rap.account_id = raup.account_id
  ),

  proxies1 AS (
    SELECT
      prox1.proxy_id AS top_proxy_id,
      prox1.account_id
    FROM insert_current_proxies prox1
  ),

  proxies2 AS (
    SELECT prox1.top_proxy_id, prox2.account_id
    FROM proxies1 prox1
    JOIN hafbe_app.current_account_proxies prox2 ON prox2.proxy_id = prox1.account_id
  ),

  proxies3 AS (
    SELECT prox2.top_proxy_id, prox3.account_id
    FROM proxies2 prox2
    JOIN hafbe_app.current_account_proxies prox3 ON prox3.proxy_id = prox2.account_id
  ),

  proxies4 AS (
    SELECT prox3.top_proxy_id, prox4.account_id
    FROM proxies3 prox3
    JOIN hafbe_app.current_account_proxies prox4 ON prox4.proxy_id = prox3.account_id
  ),

  proxies5 AS (
    SELECT prox4.top_proxy_id, prox5.account_id
    FROM proxies4 prox4
    JOIN hafbe_app.current_account_proxies prox5 ON prox5.proxy_id = prox4.account_id
  )

  INSERT INTO hafbe_app.recursive_account_proxies (proxy_id, account_id)
  SELECT top_proxy_id, account_id
  FROM (
    SELECT top_proxy_id, account_id FROM proxies1
    UNION
    SELECT top_proxy_id, account_id FROM proxies2
    UNION
    SELECT top_proxy_id, account_id FROM proxies3
    UNION
    SELECT top_proxy_id, account_id FROM proxies4
    UNION
    SELECT top_proxy_id, account_id FROM proxies5
  ) rap
  WHERE top_proxy_id != account_id
  ON CONFLICT ON CONSTRAINT pk_recursive_account_proxies DO NOTHING;

  -- add new witnesses per block range
  WITH limited_set AS (
    SELECT DISTINCT bia.name AS name
    FROM hive.hafbe_app_operations_view hov
    JOIN LATERAL (
      SELECT get_impacted_accounts AS name
      FROM hive.get_impacted_accounts(hov.body)
    ) bia ON TRUE
    WHERE hov.op_type_id = ANY('{42,11,7}') AND hov.block_num BETWEEN _from AND _to
    
    UNION
  
    SELECT DISTINCT name
    FROM (SELECT __vote_or_proxy_op.value->>'witness' AS name) witnesses
    WHERE witnesses.name IS NOT NULL
  )
  
  INSERT INTO hafbe_app.current_witnesses (witness_id, url, price_feed, bias, feed_age, block_size, signing_key, version)
  SELECT hav.id, NULL, NULL, NULL, NULL, NULL, NULL, '1.25.0'
  FROM limited_set ls
  JOIN hive.hafbe_app_accounts_view hav ON hav.name = ls.name
  ON CONFLICT ON CONSTRAINT pk_current_witnesses DO NOTHING;

  -- parse props for witnesses table
  SELECT INTO __prop_op
    cw.witness_id,
    (hov.body::JSON)->'value' AS value,
    hov.op_type_id, hov.timestamp, hov.id AS operation_id
  FROM hive.hafbe_app_operations_view hov
  JOIN LATERAL (
    SELECT get_impacted_accounts AS name
    FROM hive.get_impacted_accounts(hov.body)
  ) bia ON TRUE
  JOIN hive.hafbe_app_accounts_view hav ON hav.name = bia.name
  JOIN hafbe_app.current_witnesses cw ON cw.witness_id = hav.id
  WHERE hov.op_type_id = ANY('{42,30,14,11,7}') AND hov.block_num BETWEEN _from AND _to;
  
  UPDATE hafbe_app.current_witnesses cw SET url = res.prop_value FROM (
    SELECT prop_value, witness_id
    FROM (
      SELECT
        prop_value, witness_id, operation_id,
        ROW_NUMBER() OVER (PARTITION BY witness_id ORDER BY operation_id DESC) AS row_n
      FROM (
        SELECT
          __prop_op.value->>'url' AS prop_value,
          __prop_op.operation_id, __prop_op.witness_id
        WHERE __prop_op.op_type_id = 11

        UNION

        SELECT
          trim(both '"' FROM prop_value::TEXT),
          __prop_op.operation_id, __prop_op.witness_id
        FROM hive.extract_set_witness_properties(__prop_op.value->>'props')
        WHERE prop_name = 'url' AND __prop_op.op_type_id = 42
      ) parsed
      WHERE prop_value IS NOT NULL
    ) row_count
    WHERE row_n = 1
  ) res
  WHERE cw.witness_id = res.witness_id;
  
  UPDATE hafbe_app.current_witnesses cw SET
    price_feed = (res.prop_value->'base'->>'amount')::NUMERIC / (res.prop_value->'quote'->>'amount')::NUMERIC,
    bias = ((res.prop_value->'quote'->>'amount')::NUMERIC - 1000)::NUMERIC,
    feed_age = (NOW() - res.timestamp)::INTERVAL
  FROM (
    SELECT prop_value::JSON, witness_id, timestamp
    FROM (
      SELECT
        prop_value, witness_id, operation_id, timestamp,
        ROW_NUMBER() OVER (PARTITION BY witness_id ORDER BY operation_id DESC) AS row_n
      FROM (
        SELECT
          __prop_op.value->>'exchange_rate' AS prop_value,
          __prop_op.operation_id, __prop_op.witness_id, __prop_op.timestamp
        WHERE __prop_op.op_type_id = 7

        UNION

        SELECT
          prop_value::TEXT,
          __prop_op.operation_id, __prop_op.witness_id, __prop_op.timestamp
        FROM hive.extract_set_witness_properties(__prop_op.value->>'props')
        WHERE prop_name = 'hbd_exchange_rate' AND __prop_op.op_type_id = 42
      ) parsed
      WHERE prop_value IS NOT NULL
    ) row_count
    WHERE row_n = 1
  ) res
  WHERE cw.witness_id = res.witness_id;
  
  UPDATE hafbe_app.current_witnesses cw SET block_size = res.prop_value FROM (
    SELECT prop_value::INT, witness_id
    FROM (
      SELECT
        prop_value, witness_id, operation_id,
        ROW_NUMBER() OVER (PARTITION BY witness_id ORDER BY operation_id DESC) AS row_n
      FROM (
        SELECT
          __prop_op.value->'props'->>'maximum_block_size' AS prop_value,
          __prop_op.operation_id, __prop_op.witness_id
        WHERE __prop_op.op_type_id = ANY('{30,14,11}')

        UNION

        SELECT
          prop_value::TEXT,
          __prop_op.operation_id, __prop_op.witness_id
        FROM hive.extract_set_witness_properties(__prop_op.value->>'props')
        WHERE prop_name = 'maximum_block_size' AND __prop_op.op_type_id = 42
      ) parsed
      WHERE prop_value IS NOT NULL
    ) row_count
    WHERE row_n = 1
  ) res
  WHERE cw.witness_id = res.witness_id;
  
  UPDATE hafbe_app.current_witnesses cw SET signing_key = res.prop_value FROM (
    SELECT prop_value, witness_id
    FROM (
      SELECT
        prop_value, witness_id, operation_id,
        ROW_NUMBER() OVER (PARTITION BY witness_id ORDER BY operation_id DESC) AS row_n
      FROM (
        SELECT
          __prop_op.value->>'block_signing_key' AS prop_value,
          __prop_op.operation_id, __prop_op.witness_id
        WHERE __prop_op.op_type_id = 11

        UNION

        SELECT
          -- witness_set_properties_operation may contain old and new signing keys
          trim(both '"' FROM 
            (CASE WHEN ex_res1.prop_value IS NULL THEN ex_res2.prop_value ELSE ex_res1.prop_value END)::TEXT
          ),
          operation_id, witness_id
        FROM (
          SELECT __prop_op.value, __prop_op.operation_id, __prop_op.witness_id
        ) encoded_op
        LEFT JOIN LATERAL (
          SELECT prop_value
          FROM hive.extract_set_witness_properties(value->>'props')
          WHERE prop_name = 'new_signing_key'
        ) ex_res1 ON TRUE
        LEFT JOIN LATERAL (
          SELECT prop_value
          FROM hive.extract_set_witness_properties(value->>'props')
          WHERE prop_name = 'key'
        ) ex_res2 ON ex_res1.prop_value IS NULL
        WHERE __prop_op.op_type_id = 42
      ) parsed
      WHERE prop_value IS NOT NULL
    ) row_count
    WHERE row_n = 1
  ) res
  WHERE cw.witness_id = res.witness_id;

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
