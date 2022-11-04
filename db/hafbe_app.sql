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
    finished_processing_at TIMESTAMP,
    last_reported_at TIMESTAMP,
    last_reported_block INT
  );
  INSERT INTO hafbe_app.app_status (continue_processing, last_processed_block, started_processing_at, finished_processing_at, last_reported_at, last_reported_block)
  VALUES (TRUE, 0, NULL, NULL, to_timestamp(0), 0);

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

  CREATE TABLE IF NOT EXISTS hafbe_app.witnesses_cache_config (
    update_interval INTERVAL,
    last_updated_at TIMESTAMP
  );

  INSERT INTO hafbe_app.witnesses_cache_config (update_interval, last_updated_at)
  VALUES ('1 hour', to_timestamp(0));

  CREATE TABLE IF NOT EXISTS hafbe_app.witness_voters_stats_cache (
    witness_id INT,
    voter_id INT,
    vests NUMERIC,
    account_vests NUMERIC,
    proxied_vests NUMERIC,
    timestamp TIMESTAMP,

    CONSTRAINT pk_witness_voters_stats_cache PRIMARY KEY (witness_id, voter_id)
  );

  CREATE TABLE IF NOT EXISTS hafbe_app.witness_votes_cache (
    witness_id INT,
    votes NUMERIC,
    voters_num INT,

    CONSTRAINT pk_witness_votes_cache PRIMARY KEY (witness_id)
  );
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
  __balance_impacting_ops_ids INT[] = (SELECT op_type_ids_arr FROM hafbe_app.balance_impacting_op_ids);
BEGIN
  -- process vote ops
  WITH select_votes_ops AS (
    SELECT hav_w.id AS witness_id, hav_v.id AS voter_id, approve, timestamp, operation_id
    FROM (
      SELECT
        value->>'witness' AS witness,
        value->>'account' AS voter,
        (value->>'approve')::BOOLEAN AS approve,
        timestamp, operation_id
      FROM (
        SELECT
          (body::JSON)->'value' AS value,
          timestamp, id AS operation_id
        FROM hive.hafbe_app_operations_view
        WHERE op_type_id = 12 AND block_num BETWEEN _from AND _to
      ) ops_in_range
    ) vote_op
    JOIN hive.hafbe_app_accounts_view hav_w ON hav_w.name = vote_op.witness
    JOIN hive.hafbe_app_accounts_view hav_v ON hav_v.name = vote_op.voter
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
        value->>'account' AS account,
        value->>'proxy' AS proxy_account,
        CASE WHEN op_type_id = 13 THEN TRUE ELSE FALSE END AS proxy,
        timestamp, operation_id
      FROM (
        SELECT
          (body::JSON)->'value' AS value,
          timestamp, id AS operation_id, op_type_id
        FROM hive.hafbe_app_operations_view
        WHERE op_type_id = ANY('{13,91}') AND block_num BETWEEN _from AND _to
      ) ops_in_range
    ) proxy_op
    JOIN hive.hafbe_app_accounts_view hav_a ON hav_a.name = proxy_op.account
    JOIN hive.hafbe_app_accounts_view hav_p ON hav_p.name = proxy_op.proxy_account
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
  )

  DELETE FROM hafbe_app.current_account_proxies cap USING (
    SELECT account_id
    FROM select_latest_proxy_ops
    WHERE proxy IS FALSE
  ) spo
  WHERE cap.account_id = spo.account_id;

  -- add new witnesses per block range
  WITH select_witness_names AS (
    SELECT DISTINCT
      CASE WHEN op_type_id = 12 THEN
        value->>'witness'
      ELSE
        (SELECT hive.get_impacted_accounts(body))
      END AS name
    FROM (
      SELECT body, (body::JSON)->'value' AS value, op_type_id
      FROM hive.hafbe_app_operations_view
      WHERE op_type_id = ANY('{12,42,11,7}') AND block_num BETWEEN _from AND _to
    ) ops_in_range
  )
  
  INSERT INTO hafbe_app.current_witnesses (witness_id, url, price_feed, bias, feed_age, block_size, signing_key, version)
  SELECT hav.id, NULL, NULL, NULL, NULL, NULL, NULL, '1.27.0'
  FROM select_witness_names swn
  JOIN hive.hafbe_app_accounts_view hav ON hav.name = swn.name
  ON CONFLICT ON CONSTRAINT pk_current_witnesses DO NOTHING;

  -- parse props for witnesses table
  WITH select_witness_prop_ops AS (
    SELECT
      cw.witness_id,
      oir.value,
      oir.op_type_id, oir.timestamp, oir.operation_id
    FROM (
      SELECT
        bia.name,
        (body::JSON)->'value' AS value,
        op_type_id, timestamp, id AS operation_id
      FROM hive.hafbe_app_operations_view hov

      JOIN LATERAL (
        SELECT get_impacted_accounts AS name
        FROM hive.get_impacted_accounts(hov.body)
      ) bia ON TRUE
      WHERE op_type_id = ANY('{42,30,14,11,7}') AND block_num BETWEEN _from AND _to
    ) oir
    JOIN hive.hafbe_app_accounts_view hav ON hav.name = oir.name
    JOIN hafbe_app.current_witnesses cw ON cw.witness_id = hav.id
  ),

  parse_witness_set_properties_ops AS (
    SELECT
      ex_prop.prop_value, ex_prop.prop_name,
      timestamp, operation_id, witness_id
    FROM select_witness_prop_ops swpo

    JOIN LATERAL (
      SELECT
        trim(both '"' FROM prop_value::TEXT) AS prop_value,
        CASE WHEN prop_name = 'hbd_exchange_rate' THEN 'exchange_rate' ELSE prop_name END AS prop_name
      FROM hive.extract_set_witness_properties(swpo.value->>'props')
    ) ex_prop ON TRUE
    WHERE op_type_id = 42
  ),

  /*
  TODO: 
  -- witness_set_properties_operation may contain old and new signing keys
  -- new_signing_key -- key
  trim(both '"' FROM 
    (CASE WHEN ex_res1.prop_value IS NULL THEN ex_res2.prop_value ELSE ex_res1.prop_value END)::TEXT
  ),
  */  
  
  parse_witness_update_and_pow_ops AS (
    SELECT
      value->>'url' AS prop_value, 'url' AS prop_name,
      timestamp, operation_id, witness_id
    FROM select_witness_prop_ops
    WHERE op_type_id = 11

    UNION

    SELECT
      value->>'block_signing_key' AS prop_value, 'signing_key' AS prop_name,
      timestamp, operation_id, witness_id
    FROM select_witness_prop_ops
    WHERE op_type_id = 11

    UNION

    SELECT
      value->'props'->>'maximum_block_size' AS prop_value, 'block_size' AS prop_name,
      timestamp, operation_id, witness_id
    FROM select_witness_prop_ops
    WHERE op_type_id = ANY('{30,14,11}')
  ),

  parse_feed_publish_ops AS (
    SELECT
      value->>'exchange_rate' AS prop_value, 'exchange_rate' AS prop_name,
      timestamp, operation_id, witness_id
    FROM select_witness_prop_ops
    WHERE op_type_id = 7
  ),

  stack_parsed_props AS (
    SELECT prop_value, prop_name, timestamp, operation_id, witness_id
    FROM (
      SELECT
        ROW_NUMBER() OVER (PARTITION BY witness_id, prop_name ORDER BY operation_id DESC) AS row_n,
        prop_value, prop_name, timestamp, operation_id, witness_id
      FROM (
        SELECT prop_value, prop_name, timestamp, operation_id, witness_id
        FROM parse_witness_set_properties_ops

        UNION

        SELECT prop_value, prop_name, timestamp, operation_id, witness_id
        FROM parse_witness_update_and_pow_ops

        UNION

        SELECT prop_value, prop_name, timestamp, operation_id, witness_id
        FROM parse_feed_publish_ops
      ) pp
    ) row_count
    WHERE row_n = 1
  ),

  update_witness_url AS (
    UPDATE hafbe_app.current_witnesses cw SET url = spp.url FROM (
      SELECT prop_value AS url, witness_id
      FROM stack_parsed_props
      WHERE prop_name = 'url'
    ) spp
    WHERE cw.witness_id = spp.witness_id
  ),

  update_witness_exchange_rate_data AS (
    UPDATE hafbe_app.current_witnesses cw SET
      price_feed = spp.price_feed,
      bias = spp.bias,
      feed_age = spp.feed_age
    FROM (
      SELECT
        (prop_value->'base'->>'amount')::NUMERIC / (prop_value->'quote'->>'amount')::NUMERIC AS price_feed,
        ((prop_value->'quote'->>'amount')::NUMERIC - 1000)::NUMERIC AS bias,
        (NOW() - timestamp)::INTERVAL AS feed_age,
        witness_id
      FROM (
        SELECT (prop_value::JSON) AS prop_value, timestamp, witness_id
        FROM stack_parsed_props
        WHERE prop_name = 'exchange_rate'
      ) vals
    ) spp
    WHERE cw.witness_id = spp.witness_id
  ),

  update_witness_block_size AS (
    UPDATE hafbe_app.current_witnesses cw SET block_size = spp.block_size FROM (
      SELECT prop_value::INT AS block_size, witness_id
      FROM stack_parsed_props
      WHERE prop_name = 'block_size'
    ) spp
    WHERE cw.witness_id = spp.witness_id
  )

  UPDATE hafbe_app.current_witnesses cw SET signing_key = spp.signing_key FROM (
    SELECT prop_value AS signing_key, witness_id
    FROM stack_parsed_props
    WHERE prop_name = 'signing_key'
  ) spp
  WHERE cw.witness_id = spp.witness_id;

  -- get impacted vests balance for block range and update account_vests
  WITH balance_change AS (
    SELECT hav.id AS account_id, bio.amount AS vests
    FROM hive.operations_view hov

    JOIN LATERAL (
      SELECT account_name, amount
      FROM hive.get_impacted_balances(hov.body, hov.block_num > 905693)
      WHERE asset_symbol_nai = 37
    ) bio ON TRUE

    JOIN hive.accounts_view hav ON hav.name = bio.account_name
    WHERE hov.op_type_id = ANY(__balance_impacting_ops_ids) AND hov.block_num BETWEEN _from AND _to
  )

  INSERT INTO hafbe_app.account_vests (account_id, vests)
  SELECT account_id, SUM(vests) AS vests
  FROM balance_change
  GROUP BY account_id
  ON CONFLICT ON CONSTRAINT pk_account_vests DO 
    UPDATE SET vests = hafbe_app.account_vests.vests + EXCLUDED.vests
  ;
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

    IF (NOW() - (SELECT last_reported_at FROM hafbe_app.app_status LIMIT 1)) >= '5 second'::INTERVAL THEN

      RAISE NOTICE 'Last processed block %', _last_block;
      RAISE NOTICE 'Processed % blocks in 5 seconds', (SELECT _last_block - last_reported_block FROM hafbe_app.app_status LIMIT 1);
      RAISE NOTICE 'Block processing running for % minutes
      ', ROUND((EXTRACT(epoch FROM (
          SELECT NOW() - started_processing_at FROM hafbe_app.app_status LIMIT 1
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
        UPDATE hafbe_app.app_status SET finished_processing_at = NOW();
      ELSE
        CALL hafbe_app.processBlock(__next_block_range.last_block);
        __last_block := __next_block_range.last_block;
      END IF;
    
      IF __next_block_range.first_block = __next_block_range.last_block AND
        (NOW() - (SELECT last_updated_at FROM hafbe_app.witnesses_cache_config LIMIT 1)) >= 
        (SELECT update_interval FROM hafbe_app.witnesses_cache_config LIMIT 1) THEN

        RAISE NOTICE 'Updating witnesses caches';
        
        WITH select_voters_stats AS (
          SELECT witness_id, voter_id, vests, account_vests, proxied_vests
          FROM hafbe_views.voters_stats_view
        ),

        insert_witness_voters_stats_cache AS (
          INSERT INTO hafbe_app.witness_voters_stats_cache (witness_id, voter_id, vests, account_vests, proxied_vests)
          SELECT witness_id, voter_id, vests, account_vests, proxied_vests
          FROM select_voters_stats
          ON CONFLICT ON CONSTRAINT pk_witness_voters_stats_cache DO UPDATE SET
            vests = EXCLUDED.vests,
            account_vests = EXCLUDED.account_vests,
            proxied_vests = EXCLUDED.proxied_vests,
            timestamp = EXCLUDED.timestamp
        )

        INSERT INTO hafbe_app.witness_votes_cache (witness_id, votes, voters_num)
        SELECT witness_id, SUM(vests), COUNT(1)
        FROM select_voters_stats
        GROUP BY witness_id
        ON CONFLICT ON CONSTRAINT pk_witness_votes_cache DO UPDATE SET
          votes = EXCLUDED.votes,
          voters_num = EXCLUDED.voters_num
        ;

        UPDATE hafbe_app.witnesses_cache_config SET last_updated_at = NOW();

      END IF;

    END IF;

  END LOOP;

  RAISE NOTICE 'Exiting application main loop at processed block: %.', __last_block;
  PERFORM hafbe_app.storeLastProcessedBlock(__last_block);

  COMMIT;
END
$$
;
