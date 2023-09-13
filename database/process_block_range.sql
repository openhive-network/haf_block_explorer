SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_app.process_block_range_data_a(_from INT, _to INT)
RETURNS VOID
AS
$function$
DECLARE
  __balance_change RECORD;
BEGIN

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
SET cursor_tuple_fraction='0.9'
;

CREATE OR REPLACE FUNCTION hafbe_app.process_block_range_data_b(_from INT, _to INT)
RETURNS VOID
AS
$function$
BEGIN
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
SET cursor_tuple_fraction='0.9'
;

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

FOR __balance_change IN
  WITH comment_operation AS (

SELECT 
    cao.body AS body,
    cao.id AS source_op,
    cao.block_num AS source_op_block,
    cao.timestamp AS _timestamp,
    cao.op_type_id AS op_type,
    cao.body_binary,
    cao.timestamp,
    cao.op_type_id
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
  JOIN hive.hafbe_app_accounts_view a ON a.name = po.worker_account
  LEFT JOIN hafbe_app.account_parameters ap ON a.id = ap.account
  WHERE ap.account IS NULL
  ORDER BY po.worker_account, po.block_num, po.id DESC
) po_subquery ON cao.id = po_subquery.source_op
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
  JOIN hive.hafbe_app_accounts_view a ON a.name = po.worker_account
  LEFT JOIN hafbe_app.account_parameters ap ON a.id = ap.account
  WHERE ap.account IS NULL
  ORDER BY po.worker_account, po.block_num, po.id DESC
) pto_subquery ON cao.id = pto_subquery.source_op
LEFT JOIN (
  WITH selected_range AS MATERIALIZED (
  	SELECT up.id, up.author, up.permlink
    FROM hafbe_views.comments_view up
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
	 ORDER BY prd.id DESC LIMIT 1) AS prd_id
  FROM selected_range up 
)
SELECT source_op FROM (
SELECT prd.up_id AS source_op, prd.author, prd.permlink, prd.prd_id,
COALESCE(
       (SELECT 1 
        FROM 
          hafbe_views.deleted_comments_view dp
        WHERE 
          dp.author = prd.author 
          and dp.permlink = prd.permlink 
		  AND prd.prd_id IS NOT NULL
          and dp.id between prd.prd_id and prd.up_id
	   LIMIT 1),0
) as filtered FROM filtered_range prd ) as filtered2
WHERE (filtered = 0 and prd_id IS NULL) or (filtered =1 and prd_id IS NOT NULL)
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
    PERFORM hive.process_operation(__balance_change, 'hafbe_app', 'process_create_account_op');

    WHEN __balance_change.op_type = 14 OR __balance_change.op_type = 30 THEN
    PERFORM hive.process_operation(__balance_change, 'hafbe_app', 'process_pow_op');

    WHEN __balance_change.op_type = 76 THEN
    PERFORM hive.process_operation(__balance_change, 'hafbe_app', 'process_changed_recovery_account_op');

    WHEN __balance_change.op_type = 25 THEN
    PERFORM hive.process_operation(__balance_change, 'hafbe_app', 'process_recover_account_op');

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

RESET ROLE;
