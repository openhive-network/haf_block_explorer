SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_app.process_witness_stats(_from INT, _to INT)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
SET enable_bitmapscan = OFF
AS
$$
BEGIN
-- function used for calculating witnesses
-- updates table hafbe_app.current_witnesses
  WITH ops_in_range AS MATERIALIZED -- add new witnesses per block range
  (
    SELECT ov.body_binary, (ov.body)->'value' AS value, ov.op_type_id
    FROM hafbe_app.operations_view ov
    WHERE ov.op_type_id IN (12,42,11,7,14,30) 
    AND ov.block_num BETWEEN _from AND _to
  ),
  select_witness_names AS MATERIALIZED ( 
    SELECT DISTINCT
      CASE WHEN op_type_id = 12 THEN
        value->>'witness'
      ELSE
        (SELECT hive.get_impacted_accounts(body_binary))
      END AS name
    FROM ops_in_range
  )
  
  INSERT INTO hafbe_app.current_witnesses (witness_id, url, price_feed, bias, feed_updated_at, block_size, signing_key, version)
  SELECT 
    (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = swn.name) AS id,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL
  FROM select_witness_names swn
  ON CONFLICT ON CONSTRAINT pk_current_witnesses DO NOTHING;

  -- insert witness node version
  UPDATE hafbe_app.current_witnesses cw SET version = w_node.version FROM 
  (
    SELECT witness_id, version, row_n
    FROM (
      WITH get_version AS
      (
        SELECT
          cw.witness_id,
          CASE WHEN hbv.extensions->0->>'type' = 'version' THEN
            hbv.extensions->0->>'value'
          ELSE
            hbv.extensions->1->>'value'
          END AS version,
          hbv.num
        FROM hafbe_app.blocks_view hbv
        JOIN hafbe_app.current_witnesses cw ON cw.witness_id = hbv.producer_account_id
        WHERE hbv.num BETWEEN _from AND _to AND hbv.extensions IS NOT NULL
      )
      SELECT gv.witness_id, gv.version,
      ROW_NUMBER() OVER (PARTITION BY gv.witness_id ORDER BY gv.num DESC) AS row_n
      FROM get_version gv
      WHERE gv.version IS NOT NULL
    ) row_count
    WHERE row_n = 1
  ) w_node
  WHERE cw.witness_id = w_node.witness_id;

  -- parse witness url
  WITH select_ops_with_url AS (
    SELECT witness, value, op_type_id, operation_id
    FROM hafbe_views.witness_prop_op_view
    WHERE op_type_id = ANY('{42,11}') AND block_num BETWEEN _from AND _to
  ),

  select_url_from_set_witness_properties AS (
    SELECT ex_prop.url, operation_id, witness
    FROM select_ops_with_url sowu

    JOIN LATERAL (
      SELECT trim(both '"' FROM prop_value::TEXT) AS url
      FROM hive.extract_set_witness_properties(sowu.value->>'props')
      WHERE prop_name = 'url'
    ) ex_prop ON TRUE
    WHERE op_type_id = 42
  ),

  select_url_from_witness_update_op AS (
    SELECT value->>'url' AS url, operation_id, witness
    FROM select_ops_with_url
    WHERE op_type_id != 42
  )

  UPDATE hafbe_app.current_witnesses cw SET url = ops.url FROM (
    SELECT 
      (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = prop.witness) AS witness_id,
      url
    FROM (
      SELECT
        url, witness,
        ROW_NUMBER() OVER (PARTITION BY witness ORDER BY operation_id DESC) AS row_n
      FROM (
        SELECT url, operation_id, witness
        FROM select_url_from_set_witness_properties

        UNION ALL

        SELECT url, operation_id, witness
        FROM select_url_from_witness_update_op
      ) sp
      WHERE url IS NOT NULL
    ) prop
    WHERE row_n = 1
  ) ops
  WHERE cw.witness_id = ops.witness_id;
  
  -- parse witness exchange_rate
  WITH select_ops_with_exchange_rate_without_timestamp AS (
    SELECT witness, value, op_type_id, operation_id, block_num
    FROM hafbe_views.witness_prop_op_view
    WHERE op_type_id = ANY('{42,7}') AND block_num BETWEEN _from AND _to
  ),

  select_ops_with_exchange_rate AS (
    SELECT select_ops.witness, select_ops.value, select_ops.op_type_id, select_ops.operation_id, hb.created_at timestamp
    FROM select_ops_with_exchange_rate_without_timestamp select_ops
    JOIN hive.blocks_view hb ON hb.num = select_ops.block_num
  ),

  select_exchange_rate_from_set_witness_properties AS (
    SELECT ex_prop.exchange_rate, operation_id, timestamp, witness
    FROM select_ops_with_exchange_rate sower

    JOIN LATERAL (
      SELECT trim(both '"' FROM prop_value::TEXT) AS exchange_rate
      FROM hive.extract_set_witness_properties(sower.value->>'props')
      WHERE prop_name = 'hbd_exchange_rate'
    ) ex_prop ON TRUE
    WHERE op_type_id = 42
  ),

  select_exchange_rate_from_feed_publish_op AS (
    SELECT value->>'exchange_rate' AS exchange_rate, operation_id, timestamp, witness
    FROM select_ops_with_exchange_rate
    WHERE op_type_id != 42
  )

  UPDATE hafbe_app.current_witnesses cw SET
    price_feed = ops.price_feed,
    bias = ops.bias,
    feed_updated_at = ops.feed_updated_at
  FROM (
    SELECT
      (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = prop.witness) AS witness_id,
      (exchange_rate->'base'->>'amount')::NUMERIC / (exchange_rate->'quote'->>'amount')::NUMERIC AS price_feed,
      ((exchange_rate->'quote'->>'amount')::NUMERIC - 1000)::NUMERIC AS bias,
      timestamp AS feed_updated_at
    FROM (
      SELECT
        exchange_rate::JSON, witness, timestamp,
        ROW_NUMBER() OVER (PARTITION BY witness ORDER BY operation_id DESC) AS row_n
      FROM (
        SELECT exchange_rate, operation_id, timestamp, witness
        FROM select_exchange_rate_from_set_witness_properties

        UNION ALL

        SELECT exchange_rate, operation_id, timestamp, witness
        FROM select_exchange_rate_from_feed_publish_op
      ) sp
      WHERE exchange_rate IS NOT NULL
    ) prop
    WHERE row_n = 1
  ) ops
  WHERE cw.witness_id = ops.witness_id;

  -- parse witness block_size
  WITH select_ops_with_block_size AS (
    SELECT witness, value, op_type_id, operation_id
    FROM hafbe_views.witness_prop_op_view
    WHERE op_type_id = ANY('{42,11,30,14}') AND block_num BETWEEN _from AND _to
  ),

  select_block_size_from_set_witness_properties AS (
    SELECT ex_prop.block_size, operation_id, witness
    FROM select_ops_with_block_size sowbs

    JOIN LATERAL (
      SELECT trim(both '"' FROM prop_value::TEXT) AS block_size
      FROM hive.extract_set_witness_properties(sowbs.value->>'props')
      WHERE prop_name = 'maximum_block_size'
    ) ex_prop ON TRUE
    WHERE op_type_id = 42
  ),

  select_block_size_from_witness_update_op AS (
    SELECT value->'props'->>'maximum_block_size' AS block_size, operation_id, witness
    FROM select_ops_with_block_size
    WHERE op_type_id != 42
  )

  UPDATE hafbe_app.current_witnesses cw SET block_size = ops.block_size FROM (
    SELECT 
      (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = prop.witness) AS witness_id,
      block_size
    FROM (
      SELECT
        block_size::INT, witness,
        ROW_NUMBER() OVER (PARTITION BY witness ORDER BY operation_id DESC) AS row_n
      FROM (
        SELECT block_size, operation_id, witness
        FROM select_block_size_from_set_witness_properties

        UNION ALL

        SELECT block_size, operation_id, witness
        FROM select_block_size_from_witness_update_op
      ) sp
      WHERE block_size IS NOT NULL
    ) prop
    WHERE row_n = 1
  ) ops
  WHERE cw.witness_id = ops.witness_id;

  -- parse witness signing_key
  WITH select_ops_with_signing_key AS (
    SELECT witness, value, op_type_id, operation_id
    FROM hafbe_views.witness_prop_op_view
    WHERE op_type_id = ANY('{42,11}') AND block_num BETWEEN _from AND _to
  ),

  select_signing_key_from_set_witness_properties AS (
    SELECT
      CASE WHEN ex_prop2.signing_key IS NULL THEN ex_prop1.signing_key ELSE (
        CASE WHEN ex_prop1.signing_key IS NULL THEN ex_prop2.signing_key ELSE ex_prop1.signing_key END
      ) END AS signing_key,
      operation_id, witness
    FROM select_ops_with_signing_key sowsk

    LEFT JOIN LATERAL (
      SELECT trim(both '"' FROM prop_value::TEXT) AS signing_key
      FROM hive.extract_set_witness_properties(sowsk.value->>'props')
      WHERE prop_name = 'new_signing_key'
    ) ex_prop1 ON TRUE

    LEFT JOIN LATERAL (
      SELECT trim(both '"' FROM prop_value::TEXT) AS signing_key
      FROM hive.extract_set_witness_properties(sowsk.value->>'props')
      WHERE prop_name = 'key'
    ) ex_prop2 ON TRUE
    WHERE op_type_id = 42
  ),

  select_signing_key_from_witness_update_op AS (
    SELECT value->>'block_signing_key' AS signing_key, operation_id, witness
    FROM select_ops_with_signing_key
    WHERE op_type_id != 42
  )

  UPDATE hafbe_app.current_witnesses cw SET signing_key = ops.signing_key FROM (
    SELECT 
      (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = prop.witness) AS witness_id,
      signing_key
    FROM (
      SELECT
        signing_key, witness,
        ROW_NUMBER() OVER (PARTITION BY witness ORDER BY operation_id DESC) AS row_n
      FROM (
        SELECT signing_key, operation_id, witness
        FROM select_signing_key_from_set_witness_properties

        UNION ALL

        SELECT signing_key, operation_id, witness
        FROM select_signing_key_from_witness_update_op
      ) sp
      WHERE signing_key IS NOT NULL
    ) prop
    WHERE row_n = 1
  ) ops
  WHERE cw.witness_id = ops.witness_id;

  -- parse witness signing_key
  WITH select_ops_with_signing_key AS (
    SELECT witness, value, op_type_id, operation_id
    FROM hafbe_views.witness_prop_op_view
    WHERE op_type_id = ANY('{14,30}') AND block_num BETWEEN _from AND _to
  ),

  select_signing_key_from_pow AS (
    SELECT value->'work'->>'worker' AS signing_key, operation_id, witness
    FROM select_ops_with_signing_key
    WHERE op_type_id = 14
  ),

  select_signing_key_from_pow_two AS (
    SELECT value->>'new_owner_key' AS signing_key, operation_id, witness
    FROM select_ops_with_signing_key
    WHERE op_type_id = 30
  )

  UPDATE hafbe_app.current_witnesses cw SET signing_key = ops.signing_key FROM (
    SELECT 
      (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = prop.witness) AS witness_id,
      signing_key
    FROM (
      SELECT
        signing_key, witness,
        ROW_NUMBER() OVER (PARTITION BY witness ORDER BY operation_id ASC) AS row_n
      FROM (
        SELECT signing_key, operation_id, witness
        FROM select_signing_key_from_pow

        UNION ALL

        SELECT signing_key, operation_id, witness
        FROM select_signing_key_from_pow_two
      ) sp
      WHERE signing_key IS NOT NULL
    ) prop
    WHERE row_n = 1
  ) ops
  WHERE cw.witness_id = ops.witness_id AND cw.signing_key IS NULL;

      -- parse witness hbd_interest_rate
  WITH select_ops_with_hbd_interest_rate AS (
    SELECT witness, value, op_type_id, operation_id
    FROM hafbe_views.witness_prop_op_view
    WHERE op_type_id = ANY('{42,11,14,30}') AND block_num BETWEEN _from AND _to
  ),

  select_hbd_interest_rate_from_set_witness_properties AS (
    SELECT ex_prop.hbd_interest_rate, operation_id, witness
    FROM select_ops_with_hbd_interest_rate sowu

    JOIN LATERAL (
      SELECT trim(both '"' FROM prop_value::TEXT)::INT AS hbd_interest_rate
      FROM hive.extract_set_witness_properties(sowu.value->>'props')
      WHERE prop_name = 'hbd_interest_rate'
    ) ex_prop ON TRUE
    WHERE op_type_id = 42
  ),

  select_hbd_interest_rate_from_witness_update_op AS (
    SELECT (value->'props'->>'hbd_interest_rate')::INT AS hbd_interest_rate, operation_id, witness
    FROM select_ops_with_hbd_interest_rate
    WHERE op_type_id != 42
  )

  UPDATE hafbe_app.current_witnesses cw SET hbd_interest_rate = ops.hbd_interest_rate FROM (
    SELECT 
      (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = prop.witness) AS witness_id,
      hbd_interest_rate
    FROM (
      SELECT
        hbd_interest_rate, witness,
        ROW_NUMBER() OVER (PARTITION BY witness ORDER BY operation_id DESC) AS row_n
      FROM (
        SELECT hbd_interest_rate, operation_id, witness
        FROM select_hbd_interest_rate_from_set_witness_properties

        UNION ALL

        SELECT hbd_interest_rate, operation_id, witness
        FROM select_hbd_interest_rate_from_witness_update_op
      ) sp
      WHERE hbd_interest_rate IS NOT NULL
    ) prop
    WHERE row_n = 1
  ) ops
  WHERE cw.witness_id = ops.witness_id;

  -- parse witness account_creation_fee
  WITH select_ops_with_account_creation_fee AS (
    SELECT witness, value, op_type_id, operation_id
    FROM hafbe_views.witness_prop_op_view
    WHERE op_type_id = ANY('{42,11,14,30}') AND block_num BETWEEN _from AND _to
  ),

  select_account_creation_fee_from_set_witness_properties AS (
    SELECT ex_prop.account_creation_fee, operation_id, witness
    FROM select_ops_with_account_creation_fee sowu

    JOIN LATERAL (
      SELECT (prop_value->>'amount')::INT AS account_creation_fee
      FROM hive.extract_set_witness_properties(sowu.value->>'props')
      WHERE prop_name = 'account_creation_fee'
    ) ex_prop ON TRUE
    WHERE op_type_id = 42
  ),

  select_account_creation_fee_from_witness_update_op AS (
    SELECT (value->'props'->'account_creation_fee'->>'amount')::INT AS account_creation_fee, operation_id, witness
    FROM select_ops_with_account_creation_fee
    WHERE op_type_id != 42
  )

  UPDATE hafbe_app.current_witnesses cw SET account_creation_fee = ops.account_creation_fee FROM (
    SELECT 
      (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = prop.witness) AS witness_id,
      account_creation_fee
    FROM (
      SELECT
        account_creation_fee, witness,
        ROW_NUMBER() OVER (PARTITION BY witness ORDER BY operation_id DESC) AS row_n
      FROM (
        SELECT account_creation_fee, operation_id, witness
        FROM select_account_creation_fee_from_set_witness_properties

        UNION ALL

        SELECT account_creation_fee, operation_id, witness
        FROM select_account_creation_fee_from_witness_update_op
      ) sp
      WHERE account_creation_fee IS NOT NULL
    ) prop
    WHERE row_n = 1
  ) ops
  WHERE cw.witness_id = ops.witness_id;

  -- parse witness missed_blocks
  WITH select_ops_with_missed AS (
    SELECT witness
    FROM hafbe_views.witness_prop_op_view
    WHERE op_type_id = 86 AND block_num BETWEEN _from AND _to
  ),
  count_missed AS (
    SELECT COUNT(*) AS missed_blocks, witness
    FROM select_ops_with_missed
    GROUP BY witness
  )
  INSERT INTO hafbe_app.current_witnesses AS cw 
    (witness_id, missed_blocks)
  SELECT 
    (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = cm.witness),
    cm.missed_blocks
  FROM count_missed cm
  ON CONFLICT ON CONSTRAINT pk_current_witnesses DO 
  UPDATE SET 
    missed_blocks = cw.missed_blocks + EXCLUDED.missed_blocks;

  -- parse last_created_block_num
  UPDATE hafbe_app.current_witnesses cw SET last_created_block_num = blocks.last_created_block_num FROM (
    SELECT 
      bv.producer_account_id AS witness_id, 
      MAX(bv.num) AS last_created_block_num 
    FROM hafbe_app.blocks_view bv
    WHERE num BETWEEN _from AND _to
    GROUP BY bv.producer_account_id
  ) blocks
  WHERE cw.witness_id = blocks.witness_id;
END
$$;

RESET ROLE;
