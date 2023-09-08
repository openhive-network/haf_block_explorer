CREATE OR REPLACE FUNCTION hafbe_app.process_block_range_data_a(_from INT, _to INT)
RETURNS VOID
AS
$function$
DECLARE
  __balance_change RECORD;
BEGIN

FOR __balance_change IN
  SELECT 
    ov.body AS body,
    ov.op_type_id as op_type,
    ov.timestamp
  FROM hive.btracker_app_operations_view ov
  WHERE 
    ov.op_type_id IN (12,13,91,92,75)
    AND ov.block_num BETWEEN _from AND _to
  ORDER BY ov.block_num, ov.id

LOOP

  CASE 

    WHEN __balance_change.op_type = 12 THEN
    PERFORM hafbe_app.process_vote_op(__balance_change.body, __balance_change.timestamp);

    WHEN __balance_change.op_type = 13 OR __balance_change.op_type = 91 THEN
    PERFORM hafbe_app.process_proxy_ops(__balance_change.body, __balance_change.timestamp, __balance_change.op_type);

    WHEN __balance_change.op_type = 92 OR __balance_change.op_type = 75 THEN
    PERFORM hafbe_app.process_expired_accounts(__balance_change.body);
    

    ELSE
  END CASE;

END LOOP;

END
$function$
LANGUAGE 'plpgsql' VOLATILE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
SET cursor_tuple_fraction='0.9'
;

CREATE OR REPLACE FUNCTION hafbe_app.process_block_range_data_b(_from INT, _to INT)
RETURNS VOID
AS
$function$
DECLARE
  __balance_impacting_ops_ids INT[] = (SELECT op_type_ids_arr FROM hafbe_app.balance_impacting_op_ids LIMIT 1);
BEGIN
  
  WITH ops_in_range AS MATERIALIZED -- add new witnesses per block range
  (
  SELECT body_binary, (body)->'value' AS value, op_type_id
  FROM hive.hafbe_app_operations_view
  WHERE op_type_id IN (12,42,11,7) AND block_num BETWEEN _from AND _to
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

END
$function$
LANGUAGE 'plpgsql' VOLATILE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
SET enable_bitmapscan = OFF
SET cursor_tuple_fraction='0.9'
;


CREATE OR REPLACE FUNCTION hafbe_app.process_block_range_data_c(_from INT, _to INT)
RETURNS VOID
AS
$function$
DECLARE
  __balance_change RECORD;
BEGIN

FOR __balance_change IN
  WITH comment_operation AS (

SELECT 
    cao.body AS body,
    cao.id AS source_op,
    cao.block_num AS source_op_block,
    cao.timestamp AS _timestamp,
    cao.op_type_id AS op_type
FROM hive.hafbe_app_operations_view cao
LEFT JOIN (
  SELECT 
      DISTINCT ON (lvt.voter) 
      voter,
      lvt.id AS source_op
  FROM hafbe_views.votes_view lvt
  WHERE lvt.block_num BETWEEN _from AND _to
  ORDER BY voter, lvt.id DESC
) lvt_subquery ON cao.id = lvt_subquery.source_op
LEFT JOIN (
  SELECT 
      DISTINCT ON (po.worker_account) 
      worker_account,
      po.id AS source_op
  FROM hafbe_views.pow_view po
  LEFT JOIN hive.hafbe_app_accounts_view a ON a.name = po.worker_account
  LEFT JOIN hafbe_app.account_parameters ap ON a.id = ap.account
  WHERE po.block_num BETWEEN _from AND _to
  AND ap.account IS NULL
  ORDER BY worker_account, po.block_num, po.id DESC
) po_subquery ON cao.id = po_subquery.source_op
LEFT JOIN (
  SELECT 
      DISTINCT ON (pto.worker_account) 
      worker_account,
      pto.id AS source_op
  FROM hafbe_views.pow_two_view pto
  LEFT JOIN hive.hafbe_app_accounts_view a ON a.name = pto.worker_account
  LEFT JOIN hafbe_app.account_parameters ap ON a.id = ap.account
  WHERE pto.block_num BETWEEN _from AND _to
  AND ap.account IS NULL
  ORDER BY worker_account, pto.block_num, pto.id DESC
) pto_subquery ON cao.id = pto_subquery.source_op
LEFT JOIN (
 SELECT source_op FROM (
 SELECT
    up.id AS source_op, 
	coalesce((SELECT 1
    FROM 
      hafbe_views.comments_view prd
    WHERE 
      prd.author = up.author 
      AND prd.permlink = up.permlink AND prd.id < up.id 
	  AND NOT EXISTS (
        SELECT 1 
        FROM 
          hafbe_views.deleted_comments_view dp
        WHERE 
          dp.author = up.author 
          and dp.permlink = up.permlink 
          and dp.id between prd.id and up.id)
	 ORDER BY prd.id DESC LIMIT 1), 0) AS filtered
  FROM hafbe_views.comments_view up
  WHERE up.block_num BETWEEN _from AND _to 
  ORDER BY up.permlink, up.block_num, up.id DESC) as filtered2
  WHERE filtered = 0
) up_subquery ON cao.id = up_subquery.source_op
WHERE 
  (cao.op_type_id IN (9, 23, 41, 80, 76, 25, 36)
  OR (cao.op_type_id = 72 AND lvt_subquery.source_op IS NOT NULL)
  OR (cao.op_type_id = 1  AND up_subquery.source_op IS NOT NULL)
  OR (cao.op_type_id = 14 AND po_subquery.source_op IS NOT NULL)
  OR (cao.op_type_id = 30 AND pto_subquery.source_op IS NOT NULL))
  AND cao.block_num BETWEEN _from AND _to
)
  SELECT * FROM comment_operation 
  ORDER BY source_op_block, source_op

LOOP

  CASE 

    WHEN __balance_change.op_type = 9 OR __balance_change.op_type = 23 OR __balance_change.op_type = 41 OR __balance_change.op_type = 80 THEN
    PERFORM hafbe_app.process_create_account_operation(__balance_change.body, __balance_change._timestamp, __balance_change.op_type);

    WHEN __balance_change.op_type = 14 OR __balance_change.op_type = 30 THEN
    PERFORM hafbe_app.process_pow_operation(__balance_change.body, __balance_change._timestamp, __balance_change.op_type);
    
    WHEN __balance_change.op_type = 76 THEN
    PERFORM hafbe_app.process_changed_recovery_account_operation(__balance_change.body);

    WHEN __balance_change.op_type = 25 THEN
    PERFORM hafbe_app.process_recover_account_operation(__balance_change.body, __balance_change._timestamp);

    WHEN __balance_change.op_type = 36 THEN
    PERFORM hafbe_app.process_decline_voting_rights_operation(__balance_change.body);

    WHEN __balance_change.op_type = 1 THEN
    PERFORM hafbe_app.process_comment_operation(__balance_change.body, __balance_change._timestamp);

    WHEN __balance_change.op_type = 72 THEN
    PERFORM hafbe_app.process_vote_operation(__balance_change.body, __balance_change._timestamp);

    ELSE
  END CASE;

END LOOP;


END
$function$
LANGUAGE 'plpgsql' VOLATILE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
SET enable_bitmapscan = OFF
set enable_hashjoin= OFF
SET cursor_tuple_fraction='0.9'
;
