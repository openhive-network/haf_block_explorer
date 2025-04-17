SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_app.process_account_stats(_from INT, _to INT)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
SET enable_bitmapscan = OFF
SET enable_hashjoin = OFF
AS
$$
DECLARE
  _result INT;
BEGIN
-- function used for calculating witnesses
-- updates tables hafbe_app.account_posts, hafbe_app.account_parameters

--SET ENABLE_NESTLOOP TO FALSE; --TODO: Temporary patch, remove later!!!!!!!!!

  WITH comment_operation_without_timestamp AS (

    select ov.* from (
      SELECT 
        ds.body AS body,
        ds.id,
        ds.id AS source_op,
        ds.block_num,
        ds.block_num AS source_op_block,
        ds.op_type_id,
        ds.op_type_id AS op_type
    FROM hafbe_app.operations_view ds
    where ds.op_type_id IN (9, 23, 41, 80, 76, 25, 36) and ds.block_num between _from and _to
    ) ov
    LEFT JOIN (
      WITH pow AS MATERIALIZED 
      (
      SELECT  
          (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = pto.worker_account) as account_id,
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
          (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = pto.worker_account) as account_id,
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
  comment_operation AS
  (
    SELECT co_w_t.*, hb.created_at _timestamp
    FROM comment_operation_without_timestamp co_w_t
    JOIN hive.blocks_view hb ON hb.num = co_w_t.source_op_block
  ),
  balance_change AS MATERIALIZED 
  (
  SELECT 
    bc.source_op,
    (CASE 

      WHEN bc.op_type = 9 OR bc.op_type = 23 OR bc.op_type = 41 THEN
      hafbe_backend.process_create_account_operation(bc.body, bc._timestamp, bc.op_type)

      WHEN bc.op_type = 80 THEN
      hafbe_backend.process_created_account_operation(bc.body, bc._timestamp, COALESCE( ( SELECT ah.block_num < bc.source_op_block FROM hafd.applied_hardforks ah WHERE hardfork_num = 11 ), FALSE ))

      WHEN bc.op_type = 14 OR bc.op_type = 30 THEN
      hafbe_backend.process_pow_operation(bc.body, bc._timestamp, bc.op_type)
      
      WHEN bc.op_type = 76 THEN
      hafbe_backend.process_changed_recovery_account_operation(bc.body)

      WHEN bc.op_type = 25 THEN
      hafbe_backend.process_recover_account_operation(bc.body, bc._timestamp)

      WHEN bc.op_type = 36 THEN
      hafbe_backend.process_decline_voting_rights_operation(bc.body)
    END)

  FROM comment_operation bc
  ORDER BY bc.source_op_block, bc.source_op
  )
  SELECT COUNT(*) FROM balance_change INTO _result;

-- parse witness pending_claimed_accounts
  WITH select_ops_with_claimed AS (
    SELECT 
      (body -> 'value' ->> 'creator') AS account,
      (
        CASE WHEN ov.op_type_id = 22 THEN
          1
        ELSE
          -1
        END
      ) AS claimed_account
    FROM hafbe_app.operations_view ov
    WHERE ov.op_type_id IN (22,23) AND ov.block_num BETWEEN _from AND _to
  ),
  count_claimed AS (
    SELECT 
      so.account,
      SUM(so.claimed_account) AS claimed_account
    FROM select_ops_with_claimed so
    GROUP BY so.account
  )
  INSERT INTO hafbe_app.account_parameters AS ap 
    (account, pending_claimed_accounts)
  SELECT 
    (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = cm.account),
    cm.claimed_account
  FROM count_claimed cm
  ON CONFLICT ON CONSTRAINT pk_account_parameters DO 
  UPDATE SET 
    pending_claimed_accounts = ap.pending_claimed_accounts + EXCLUDED.pending_claimed_accounts;

END
$$;

RESET ROLE;
