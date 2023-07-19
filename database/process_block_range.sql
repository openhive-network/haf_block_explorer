CREATE OR REPLACE FUNCTION hafbe_app.process_block_range_data_c(_from INT, _to INT)
RETURNS VOID
AS
$function$
DECLARE
  __balance_impacting_ops_ids INT[] = (SELECT op_type_ids_arr FROM hafbe_app.balance_impacting_op_ids LIMIT 1);
  ___balance_change RECORD;
BEGIN
  -- process vote ops
WITH raw_ops AS MATERIALIZED
  (
  SELECT (ov.body::jsonb)->'value' AS value,
          ov.timestamp,
          ov.id AS operation_id
  FROM hive.hafbe_app_operations_view ov
  WHERE ov.op_type_id = 12 AND ov.block_num BETWEEN _from AND _to
  ),
  source_ops AS MATERIALIZED
  (
   SELECT ro.value->>'witness' AS witness,
          ro.value->>'account' AS voter,
          (ro.value->'approve')::BOOLEAN AS approve,
          timestamp, operation_id
    from raw_ops ro
  ),
  select_votes_ops AS MATERIALIZED
  (
  SELECT hav_w.id AS witness_id, hav_v.id AS voter_id, approve, timestamp, operation_id
    FROM source_ops vote_op
    --- Warning Here we can use `hive.accounts_view` instead of `hive.hafbe_app_accounts_view`,
    --- since set of operations being visible to hafbe_app is already constrained by `hive.hafbe_app_operations_view`
    JOIN hive.accounts_view hav_w ON hav_w.name = vote_op.witness
    JOIN hive.accounts_view hav_v ON hav_v.name = vote_op.voter
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

  WITH raw_ops AS MATERIALIZED -- process proxy ops
  (
    SELECT (ov.body::jsonb)->'value' AS value,
           ov.timestamp,
           ov.id AS operation_id,
           ov.op_type_id
  FROM hive.hafbe_app_operations_view ov
  WHERE ov.op_type_id IN (13,91) AND ov.block_num BETWEEN _from AND _to
  ),
  source_ops AS MATERIALIZED
  (
    SELECT ro.value->>'account' AS account,
           ro.value->>'proxy' AS proxy_account,
           CASE WHEN ro.op_type_id = 13 THEN TRUE ELSE FALSE END AS proxy,
           ro.timestamp,
           ro.operation_id
    FROM raw_ops ro
  ),
  select_proxy_ops AS MATERIALIZED
  (
    SELECT hav_a.id AS account_id, hav_p.id AS proxy_id, proxy, timestamp, operation_id
    FROM source_ops proxy_op
    --- Warning Here we can use `hive.accounts_view` instead of `hive.hafbe_app_accounts_view`,
    --- since set of operations being visible to hafbe_app is already constrained by `hive.hafbe_app_operations_view`
    JOIN hive.accounts_view hav_a ON hav_a.name = proxy_op.account
    JOIN hive.accounts_view hav_p ON hav_p.name = proxy_op.proxy_account
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
  WHERE cap.account_id = spo.account_id
  ;

  
  WITH ops_in_range AS MATERIALIZED -- add new witnesses per block range
  (
  SELECT body, (body::jsonb)->'value' AS value, op_type_id
  FROM hive.hafbe_app_operations_view
  WHERE op_type_id IN (12,42,11,7) AND block_num BETWEEN _from AND _to
  ),
  select_witness_names AS MATERIALIZED ( 
    SELECT DISTINCT
      CASE WHEN op_type_id = 12 THEN
        value->>'witness'
      ELSE
        (SELECT hive.get_impacted_accounts(body))
      END AS name
    FROM ops_in_range
  )
  
  INSERT INTO hafbe_app.current_witnesses (witness_id, url, price_feed, bias, feed_updated_at, block_size, signing_key, version)
  SELECT hav.id, NULL, NULL, NULL, NULL, NULL, NULL, NULL
  FROM select_witness_names swn
  JOIN hive.hafbe_app_accounts_view hav ON hav.name = swn.name
  ON CONFLICT ON CONSTRAINT pk_current_witnesses DO NOTHING;

  -- insert witness node version
  UPDATE hafbe_app.current_witnesses cw SET version = w_node.version FROM (
    SELECT witness_id, version
    FROM (
      SELECT
        cw.witness_id,
        CASE WHEN extensions->0->>'type' = 'version' THEN
          extensions->0->>'value'
        ELSE
          extensions->1->>'value'
        END AS version,
        ROW_NUMBER() OVER (PARTITION BY cw.witness_id ORDER BY num DESC) AS row_n
      FROM hive.hafbe_app_blocks_view hbv
      JOIN hafbe_app.current_witnesses cw ON cw.witness_id = hbv.producer_account_id
      WHERE num BETWEEN _from AND _to AND extensions IS NOT NULL
    ) row_count
    WHERE row_n = 1 AND version IS NOT NULL
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
    SELECT hav.id AS witness_id, url
    FROM (
      SELECT
        url, witness,
        ROW_NUMBER() OVER (PARTITION BY witness ORDER BY operation_id DESC) AS row_n
      FROM (
        SELECT url, operation_id, witness
        FROM select_url_from_set_witness_properties

        UNION

        SELECT url, operation_id, witness
        FROM select_url_from_witness_update_op
      ) sp
      WHERE url IS NOT NULL
    ) prop
    JOIN hive.accounts_view hav ON hav.name = prop.witness
    WHERE row_n = 1
  ) ops
  WHERE cw.witness_id = ops.witness_id;
  
  -- parse witness exchange_rate
  WITH select_ops_with_exchange_rate AS (
    SELECT witness, value, op_type_id, operation_id, timestamp
    FROM hafbe_views.witness_prop_op_view
    WHERE op_type_id = ANY('{42,7}') AND block_num BETWEEN _from AND _to
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
      hav.id AS witness_id,
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

        UNION

        SELECT exchange_rate, operation_id, timestamp, witness
        FROM select_exchange_rate_from_feed_publish_op
      ) sp
      WHERE exchange_rate IS NOT NULL
    ) prop
    JOIN hive.accounts_view hav ON hav.name = prop.witness
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
    SELECT hav.id AS witness_id, block_size
    FROM (
      SELECT
        block_size::INT, witness,
        ROW_NUMBER() OVER (PARTITION BY witness ORDER BY operation_id DESC) AS row_n
      FROM (
        SELECT block_size, operation_id, witness
        FROM select_block_size_from_set_witness_properties

        UNION

        SELECT block_size, operation_id, witness
        FROM select_block_size_from_witness_update_op
      ) sp
      WHERE block_size IS NOT NULL
    ) prop
    JOIN hive.accounts_view hav ON hav.name = prop.witness
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
    SELECT hav.id AS witness_id, signing_key
    FROM (
      SELECT
        signing_key, witness,
        ROW_NUMBER() OVER (PARTITION BY witness ORDER BY operation_id DESC) AS row_n
      FROM (
        SELECT signing_key, operation_id, witness
        FROM select_signing_key_from_set_witness_properties

        UNION

        SELECT signing_key, operation_id, witness
        FROM select_signing_key_from_witness_update_op
      ) sp
      WHERE signing_key IS NOT NULL
    ) prop
    JOIN hive.accounts_view hav ON hav.name = prop.witness
    WHERE row_n = 1
  ) ops
  WHERE cw.witness_id = ops.witness_id;

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

  WITH vote_operation AS (
    SELECT 
      DISTINCT ON ((lvt.body::jsonb)->'value'->>'voter') body::jsonb AS _body,
      lvt.id AS source_op,
      lvt.block_num AS source_op_block,
      lvt.timestamp AS _timestamp
		FROM hive.hafbe_app_operations_view lvt
		WHERE lvt.op_type_id = 72
		AND lvt.block_num BETWEEN _from AND _to
		ORDER BY (lvt.body::jsonb)->'value'->>'voter', lvt.id DESC
  ),
  select_votes AS (
    SELECT * FROM vote_operation 
    ORDER BY source_op_block, source_op
  )
  INSERT INTO hafbe_app.account_posts
  (
  account,
  last_vote_time
  ) 
  SELECT
    (SELECT id FROM hive.hafbe_app_accounts_view WHERE name = (_body)->'value'->>'voter'),
    _timestamp
  FROM select_votes

  ON CONFLICT ON CONSTRAINT pk_account_posts
  DO UPDATE SET
      last_vote_time = EXCLUDED.last_vote_time;

FOR ___balance_change IN
  WITH comment_operation AS (
  	SELECT 
      DISTINCT ON ((up.body::jsonb)->'value'->>'permlink') body::jsonb AS _body,
      up.id AS source_op,
      up.block_num AS source_op_block,
      up.op_type_id AS op_type,
      up.timestamp AS _timestamp
		FROM hive.hafbe_app_operations_view up
		WHERE up.op_type_id = 1
		AND up.block_num BETWEEN _from AND _to
		ORDER BY (up.body::jsonb)->'value'->>'permlink', up.block_num, up.id DESC
  )
  SELECT * FROM comment_operation 
  ORDER BY source_op_block, source_op

LOOP

  IF NOT EXISTS (
    SELECT 1
    FROM hafbe_app.comments_view ov
    WHERE 
      ov.permlink = (___balance_change._body)->'value'->>'permlink'
      AND ov.author = (___balance_change._body)->'value'->>'author'
      AND ov.block_num BETWEEN 1 AND _from
  ) THEN
    IF NULLIF((___balance_change._body)->'value'->>'parent_author', '') IS NULL THEN

      INSERT INTO hafbe_app.account_posts
      (
        account,
        last_post,
        last_root_post,
        post_count
      ) 
      SELECT
        (SELECT id FROM hive.hafbe_app_accounts_view WHERE name = (___balance_change._body)->'value'->>'author'),
        ___balance_change._timestamp,
        ___balance_change._timestamp,
        1

      ON CONFLICT ON CONSTRAINT pk_account_posts
      DO UPDATE SET
        last_post = EXCLUDED.last_post,
        last_root_post = EXCLUDED.last_root_post,
        post_count = hafbe_app.account_posts.post_count + EXCLUDED.post_count;

    ELSE

      INSERT INTO hafbe_app.account_posts
      (
        account,
        last_post,
        post_count
      ) 
      SELECT
        (SELECT id FROM hive.hafbe_app_accounts_view WHERE name = (___balance_change._body)->'value'->>'author'),
        ___balance_change._timestamp,
        1

      ON CONFLICT ON CONSTRAINT pk_account_posts
      DO UPDATE SET
        last_post = EXCLUDED.last_post,
        post_count = hafbe_app.account_posts.post_count + EXCLUDED.post_count;

    END IF;

  END IF;

END LOOP;
END
$function$
LANGUAGE 'plpgsql' VOLATILE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
SET enable_bitmapscan = OFF
;
