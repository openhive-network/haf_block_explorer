SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_app.process_block_range_data_a(_from INT, _to INT)
RETURNS VOID
AS
$function$
DECLARE
  _result INT;
BEGIN
-- function used to calculate witness votes and proxies
-- updates tables hafbe_app.current_account_proxies, hafbe_app.current_witness_votes, hafbe_app.witness_votes_history, hafbe_app.account_proxies_history
WITH proxy_ops AS MATERIALIZED 
(
  SELECT 
    ov.body AS body,
    ov.id,
    ov.block_num,
    ov.op_type_id as op_type,
    ov.timestamp
  FROM hive.btracker_app_operations_view ov
  WHERE 
    ov.op_type_id IN (12,13,91,92,75)
    AND ov.block_num BETWEEN _from AND _to
),
balance_change AS MATERIALIZED 
(
SELECT
  bc.id,
  (CASE 

    WHEN bc.op_type = 12 THEN
     hafbe_app.process_vote_op(bc.body, bc.timestamp)

    WHEN bc.op_type = 13 OR bc.op_type = 91 THEN
     hafbe_app.process_proxy_ops(bc.body, bc.timestamp, bc.op_type)

    WHEN bc.op_type = 92 OR bc.op_type = 75 THEN
     hafbe_app.process_expired_accounts(bc.body)
  END)
FROM proxy_ops bc
ORDER BY bc.block_num, bc.id
)

SELECT COUNT(*) FROM balance_change INTO _result;

END
$function$
LANGUAGE 'plpgsql' VOLATILE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF;

CREATE OR REPLACE FUNCTION hafbe_app.process_block_range_data_b(_from INT, _to INT)
RETURNS VOID
AS
$function$
DECLARE
  __balance_impacting_ops_ids INT[] = (SELECT op_type_ids_arr FROM hafbe_app.balance_impacting_op_ids LIMIT 1);
BEGIN
-- function used for calculating witnesses
-- updates table hafbe_app.current_witnesses

  WITH ops_in_range AS MATERIALIZED -- add new witnesses per block range
  (
    SELECT ov.body_binary, (ov.body)->'value' AS value, ov.op_type_id
    FROM hive.hafbe_app_operations_view ov
    WHERE ov.op_type_id IN (12,42,11,7) 
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
    (SELECT av.id FROM hive.accounts_view av WHERE av.name = swn.name) AS id,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL
  FROM select_witness_names swn
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
    SELECT 
      (SELECT av.id FROM hive.accounts_view av WHERE av.name = prop.witness) AS witness_id,
      url
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
      (SELECT av.id FROM hive.accounts_view av WHERE av.name = prop.witness) AS witness_id,
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
      (SELECT av.id FROM hive.accounts_view av WHERE av.name = prop.witness) AS witness_id,
      block_size
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
      (SELECT av.id FROM hive.accounts_view av WHERE av.name = prop.witness) AS witness_id,
      signing_key
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
    WHERE row_n = 1
  ) ops
  WHERE cw.witness_id = ops.witness_id;

      -- parse witness hbd_interest_rate
  WITH select_ops_with_hbd_interest_rate AS (
    SELECT witness, value, op_type_id, operation_id
    FROM hafbe_views.witness_prop_op_view
    WHERE op_type_id = ANY('{42,11}') AND block_num BETWEEN _from AND _to
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
    WHERE op_type_id = 11
  )

  UPDATE hafbe_app.current_witnesses cw SET hbd_interest_rate = ops.hbd_interest_rate FROM (
    SELECT 
      (SELECT av.id FROM hive.accounts_view av WHERE av.name = prop.witness) AS witness_id,
      hbd_interest_rate
    FROM (
      SELECT
        hbd_interest_rate, witness,
        ROW_NUMBER() OVER (PARTITION BY witness ORDER BY operation_id DESC) AS row_n
      FROM (
        SELECT hbd_interest_rate, operation_id, witness
        FROM select_hbd_interest_rate_from_set_witness_properties

        UNION

        SELECT hbd_interest_rate, operation_id, witness
        FROM select_hbd_interest_rate_from_witness_update_op
      ) sp
      WHERE hbd_interest_rate IS NOT NULL
    ) prop
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
SET cursor_tuple_fraction = '0.9';


CREATE OR REPLACE FUNCTION hafbe_app.process_block_range_data_c(_from INT, _to INT)
RETURNS VOID
AS
$function$
DECLARE
  _result INT;
BEGIN
-- function used for calculating witnesses
-- updates tables hafbe_app.account_posts, hafbe_app.account_parameters

--SET ENABLE_NESTLOOP TO FALSE; --TODO: Temporary patch, remove later!!!!!!!!!

WITH comment_operation AS (

select ov.* from (
	SELECT 
  ds.body AS body,
  ds.id,
  ds.id AS source_op,
  ds.block_num,
	ds.block_num AS source_op_block,
  ds.timestamp AS _timestamp,
  ds.op_type_id,
  ds.op_type_id AS op_type
FROM hive.hafbe_app_operations_view ds
where ds.op_type_id IN (9, 23, 41, 80, 76, 25, 36) and ds.block_num between _from and _to
) ov
LEFT JOIN (
  WITH pow AS MATERIALIZED 
  (
  SELECT  
      (SELECT av.id FROM hive.accounts_view av WHERE av.name = pto.worker_account) as account_id,
      pto.id,
      pto.block_num
  FROM hafbe_views.pow_view pto
  WHERE pto.block_num BETWEEN _from AND _to
  ),
  distint_accounts AS MATERIALIZED 
  (
  SELECT 
      DISTINCT ON (pw.account_id) 
      pw.account_id,
      pw.id,
      pw.block_num
  FROM pow pw
  )
  SELECT 
  	  da.account_id AS source_op 
  FROM distint_accounts da
  LEFT JOIN hafbe_app.account_parameters ap ON ap.account = da.account_id 
  WHERE ap.account IS NULL
  ORDER BY da.account_id, da.block_num, da.id DESC
) po_subquery ON ov.id = po_subquery.source_op
LEFT JOIN (
  WITH pow AS MATERIALIZED 
  (
  SELECT  
      (SELECT av.id FROM hive.accounts_view av WHERE av.name = pto.worker_account) as account_id,
      pto.id,
      pto.block_num
  FROM hafbe_views.pow_two_view pto
  WHERE pto.block_num BETWEEN _from AND _to
  ),
  distint_accounts AS MATERIALIZED 
  (
  SELECT 
      DISTINCT ON (pw.account_id) 
      pw.account_id,
      pw.id,
      pw.block_num
  FROM pow pw
  )
  SELECT 
  	  da.account_id AS source_op 
  FROM distint_accounts da
  LEFT JOIN hafbe_app.account_parameters ap ON ap.account = da.account_id 
  WHERE ap.account IS NULL
  ORDER BY da.account_id, da.block_num, da.id DESC
) pto_subquery ON ov.id = pto_subquery.source_op
WHERE 
  (ov.op_type_id IN (9, 23, 41, 80, 76, 25, 36)
  OR (ov.op_type_id = 14 AND po_subquery.source_op IS NOT NULL)
  OR (ov.op_type_id = 30 AND pto_subquery.source_op IS NOT NULL))
  AND ov.block_num BETWEEN _from AND _to
),
balance_change AS MATERIALIZED 
(
SELECT 
  bc.source_op,
  (CASE 

    WHEN bc.op_type = 9 OR bc.op_type = 23 OR bc.op_type = 41 THEN
     hafbe_app.process_create_account_operation(bc.body, bc._timestamp, bc.op_type)

    WHEN bc.op_type = 80 THEN
     hafbe_app.process_created_account_operation(bc.body, bc._timestamp, COALESCE( ( SELECT ah.block_num < bc.source_op_block FROM hive.applied_hardforks ah WHERE hardfork_num = 11 ), FALSE ))

    WHEN bc.op_type = 14 OR bc.op_type = 30 THEN
     hafbe_app.process_pow_operation(bc.body, bc._timestamp, bc.op_type)
    
    WHEN bc.op_type = 76 THEN
     hafbe_app.process_changed_recovery_account_operation(bc.body)

    WHEN bc.op_type = 25 THEN
     hafbe_app.process_recover_account_operation(bc.body, bc._timestamp)

    WHEN bc.op_type = 36 THEN
     hafbe_app.process_decline_voting_rights_operation(bc.body)
  END)

FROM comment_operation bc
ORDER BY bc.source_op_block, bc.source_op
)
SELECT COUNT(*) FROM balance_change INTO _result;

END
$function$
LANGUAGE 'plpgsql' VOLATILE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
SET enable_bitmapscan = OFF
SET enable_hashjoin = OFF;

/*

-- This query is used to count how many posts were made by each account
-- We need to take into consideration that post can be made first time, updated or deleted and reposted
-- indexes used in this query:
-- hive_operations_permlink_author on comment_operation (op_type_id = 1) used in hafbe_views.comments_view
-- hive_operations_delete_permlink_author on delete_comment_operation (op_type_id = 17) used in hafbe_views.deleted_comments_view
  WITH selected_range AS MATERIALIZED (
  	SELECT up.id, up.author, up.permlink
    FROM hafbe_views.comments_view up
-- First we found every comment that happened in the block_range, but we need to check if either of them are updates or original comments
  	WHERE up.block_num BETWEEN _from AND _to
  ),
filtered_range AS MATERIALIZED (
 SELECT up.id AS up_id, up.author, up.permlink,
	(SELECT prd.id
    FROM 
      hafbe_views.comments_view prd
    WHERE 
      prd.author = up.author 
      AND prd.permlink = up.permlink AND prd.id < up.id
-- To do that we look in the subquery for each comment if there was a comment with the same author and permlink
-- If prd.id was found that means there is possibility that this comment is and update and we don't count it
-- But there is possibility too that between this two comments there was delete_comment_operation and it means that this comment counts as an original
	 ORDER BY prd.id DESC LIMIT 1) AS prd_id
  FROM selected_range up 
)
SELECT source_op FROM (
SELECT prd.up_id AS source_op, prd.author, prd.permlink, prd.prd_id,
-- We are looking for delete_comment_operation between prd.prd_id and prd.up_id with the same permlink and author
COALESCE(
       (SELECT 1 
        FROM 
          hafbe_views.deleted_comments_view dp
        WHERE 
          dp.author = prd.author 
          AND dp.permlink = prd.permlink 
		      AND prd.prd_id IS NOT NULL
-- If prd.prd_id is null that means that the comment is original (and subquery returns 0 and prd.prd_id IS NULL)
          AND dp.id between prd.prd_id AND prd.up_id
-- If there was delete_comment_operation between this operations it means that the post was reposted and it counts 
-- (and subquery returns 1 and prd.prd_id IS NOT NULL)
	   LIMIT 1),0
) as filtered FROM filtered_range prd ) as filtered2
WHERE (filtered = 0 AND prd_id IS NULL) or (filtered =1 AND prd_id IS NOT NULL)
-- So there is two possibilities that we count found posts:
-- (filtered = 0 and prd_id IS NULL) -original comment 
-- (filtered = 1 prd_id IS NOT NULL) -reposted post

-- The third possibility is (filtered = 0 AND prd_id IS NOT NULL) means that: prd.up_id is and update of prd.prd_id (we dont count it)

CREATE OR REPLACE VIEW hafbe_views.deleted_comments_view
AS
  SELECT
    ov.body-> 'value'->> 'author' AS author,
    ov.body-> 'value'->> 'permlink' AS permlink,
    ov.block_num,
    ov.id
  FROM 
    hive.hafbe_app_operations_view ov
  WHERE 
    ov.op_type_id =17;

CREATE OR REPLACE VIEW hafbe_views.comments_view
AS
  SELECT
    (ov.body)->'value'->>'author' AS author,
    (ov.body)->'value'->>'permlink' AS permlink,
    ov.block_num,
    ov.id
  FROM
    hive.hafbe_app_operations_view ov
  WHERE 
    ov.op_type_id = 1;

*/



RESET ROLE;
