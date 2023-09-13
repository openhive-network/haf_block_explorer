SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_app.process_block_range_data_a(_from INT, _to INT)
RETURNS VOID
AS
$function$
DECLARE
  __balance_change RECORD;
BEGIN
-- function used to calculate witness votes and proxies
-- updates tables hafbe_app.current_account_proxies, hafbe_app.current_witness_votes, hafbe_app.witness_votes_history, hafbe_app.account_proxies_history

PERFORM hive.process_operation(op, 'hafbe_app', 'process_op_a')
FROM hive.hafbe_app_operations_view AS op
WHERE op.op_type_id IN (12,13,75,91,92) AND op.block_num BETWEEN _from AND _to
ORDER BY op.id ASC;

END
$function$
LANGUAGE 'plpgsql' VOLATILE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
SET cursor_tuple_fraction = '0.9';

CREATE OR REPLACE FUNCTION hafbe_app.process_block_range_data_b(_from INT, _to INT)
RETURNS VOID
AS
$function$
BEGIN
-- function used for calculating witnesses
-- updates table hafbe_app.current_witnesses

  PERFORM op.id, hive.process_operation(op, 'hafbe_app', 'add_new_witness')
  FROM hive.hafbe_app_operations_view AS op
  WHERE op.op_type_id IN (12,42,11,7) AND op.block_num BETWEEN _from AND _to
  ORDER BY op.id ASC;

  -- parse witness url
  PERFORM op.operation_id, hive.process_operation(op, 'hafbe_app', 'parse_witness_url')
  FROM hafbe_views.witness_prop_op_view AS op
  WHERE op.op_type_id IN (42,11) AND op.block_num BETWEEN _from AND _to
  ORDER BY op.operation_id;

  -- parse witness exchange_rate
  PERFORM op.operation_id, hive.process_operation(op, 'hafbe_app', 'parse_witness_exchange_rate')
  FROM hafbe_views.witness_prop_op_view AS op
  WHERE op.op_type_id IN (42,7) AND op.block_num BETWEEN _from AND _to
  ORDER BY op.operation_id;

  -- parse witness block_size
  PERFORM op.operation_id, hive.process_operation(op, 'hafbe_app', 'parse_witness_block_size')
  FROM hafbe_views.witness_prop_op_view AS op
  WHERE op.op_type_id IN (42,11,30,14) AND op.block_num BETWEEN _from AND _to
  ORDER BY op.operation_id;

  -- parse witness signing_key
  PERFORM op.operation_id, hive.process_operation(op, 'hafbe_app', 'parse_witness_signing_key')
  FROM hafbe_views.witness_prop_op_view AS op
  WHERE op.op_type_id IN (42,11) AND op.block_num BETWEEN _from AND _to
  ORDER BY op.operation_id;

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

END
$function$
LANGUAGE 'plpgsql' VOLATILE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
SET enable_bitmapscan = OFF
SET cursor_tuple_fraction = '0.9';

-- TODO: temporary type
DROP type IF EXISTS tt;
CREATE type tt AS (
  body JSONB,
  source_op BIGINT,
  source_block_op INT,
  _timestamp TIMESTAMP,
  op_type SMALLINT,
  body_binary hive.operation,
  "timestamp" TIMESTAMP,
  op_type_id SMALLINT
);

CREATE OR REPLACE FUNCTION hafbe_app.process_block_range_data_c(_from INT, _to INT)
RETURNS VOID
AS
$function$
DECLARE
  __balance_change tt;
BEGIN
-- function used for calculating witnesses
-- updates tables hafbe_app.account_posts, hafbe_app.account_parameters

SET ENABLE_NESTLOOP TO FALSE; --TODO: Temporary patch, remove later!!!!!!!!!

FOR __balance_change IN
  WITH comment_operation AS (

SELECT 
    ov.body AS body,
    ov.id AS source_op,
    ov.block_num AS source_op_block,
    ov.timestamp AS _timestamp,
    ov.op_type_id AS op_type,
    ov.body_binary,
    ov.timestamp,
    ov.op_type_id
FROM hive.hafbe_app_operations_view ov
LEFT JOIN (
  WITH pow AS MATERIALIZED (
  SELECT 
      DISTINCT ON (pto.worker_account) 
      worker_account,
      pto.id,
      pto.block_num
  FROM hafbe_views.pow_view pto
  WHERE pto.block_num BETWEEN _from AND _to
  )
  SELECT po.id AS source_op FROM pow po
  JOIN hive.hafbe_app_accounts_view av ON av.name = po.worker_account
  LEFT JOIN hafbe_app.account_parameters ap ON av.id = ap.account
  WHERE ap.account IS NULL
  ORDER BY po.worker_account, po.block_num, po.id DESC
) po_subquery ON ov.id = po_subquery.source_op
LEFT JOIN (
  WITH pow_two AS MATERIALIZED (
  SELECT 
      DISTINCT ON (pto.worker_account) 
      worker_account,
      pto.id,
      pto.block_num
  FROM hafbe_views.pow_two_view pto
  WHERE pto.block_num BETWEEN _from AND _to
  )
  SELECT po.id AS source_op FROM pow_two po
  JOIN hive.hafbe_app_accounts_view av ON av.name = po.worker_account
  LEFT JOIN hafbe_app.account_parameters ap ON av.id = ap.account
  WHERE ap.account IS NULL
  ORDER BY po.worker_account, po.block_num, po.id DESC
) pto_subquery ON ov.id = pto_subquery.source_op
WHERE 
  (ov.op_type_id IN (9, 23, 41, 80, 76, 25, 36)
  OR (ov.op_type_id = 14 AND po_subquery.source_op IS NOT NULL)
  OR (ov.op_type_id = 30 AND pto_subquery.source_op IS NOT NULL))
  AND ov.block_num BETWEEN _from AND _to
)
SELECT * FROM comment_operation
ORDER BY source_op_block, source_op

LOOP

  CASE 

    WHEN __balance_change.op_type = 9 OR __balance_change.op_type = 23 OR __balance_change.op_type = 41 OR __balance_change.op_type = 80 THEN
    PERFORM hive.process_operation(__balance_change, 'hafbe_app', 'process_create_account_op');

    WHEN __balance_change.op_type = 14 OR __balance_change.op_type = 30 THEN
    PERFORM hive.process_operation(__balance_change, 'hafbe_app', 'process_pow_op');

    WHEN __balance_change.op_type = 76 THEN
    PERFORM hive.process_operation(__balance_change, 'hafbe_app', 'process_changed_recovery_account_op');

    WHEN __balance_change.op_type = 25 THEN
    PERFORM hive.process_operation(__balance_change, 'hafbe_app', 'process_recover_account_op');

    WHEN __balance_change.op_type = 36 THEN
    PERFORM hafbe_app.process_decline_voting_rights_operation(__balance_change.body);

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
SET enable_hashjoin = OFF
SET cursor_tuple_fraction = '0.9';

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
