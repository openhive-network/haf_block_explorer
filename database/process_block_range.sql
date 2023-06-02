SET ROLE hafbe_owner;

DROP FUNCTION IF EXISTS hafbe_app.process_operation;
CREATE OR REPLACE FUNCTION hafbe_app.process_operation(
  op RECORD,
  op_type smallint,
  namespace TEXT,
  proc TEXT
)
RETURNS void
LANGUAGE plpgsql
VOLATILE
AS $BODY$
BEGIN
  BEGIN
    CASE op_type OF
      WHEN 0 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.vote_operation)', namespace, proc) USING op;
      WHEN 1 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.comment_operation)', namespace, proc) USING op;
      WHEN 2 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.transfer_operation)', namespace, proc) USING op;
      WHEN 3 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.transfer_to_vesting_operation)', namespace, proc) USING op;
      WHEN 4 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.withdraw_vesting_operation)', namespace, proc) USING op;
      WHEN 5 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.limit_order_create_operation)', namespace, proc) USING op;
      WHEN 6 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.limit_order_cancel_operation)', namespace, proc) USING op;
      WHEN 7 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.feed_publish_operation)', namespace, proc) USING op;
      WHEN 8 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.convert_operation)', namespace, proc) USING op;
      WHEN 9 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.account_create_operation)', namespace, proc) USING op;
      WHEN 10 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.account_update_operation)', namespace, proc) USING op;
      WHEN 11 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.witness_update_operation)', namespace, proc) USING op;
      WHEN 12 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.account_witness_vote_operation)', namespace, proc) USING op;
      WHEN 13 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.account_witness_proxy_operation)', namespace, proc) USING op;
      WHEN 14 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.pow_operation)', namespace, proc) USING op;
      WHEN 15 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.custom_operation)', namespace, proc) USING op;
      WHEN 16 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.witness_block_approve_operation)', namespace, proc) USING op;
      WHEN 17 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.delete_comment_operation)', namespace, proc) USING op;
      WHEN 18 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.custom_json_operation)', namespace, proc) USING op;
      WHEN 19 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.comment_options_operation)', namespace, proc) USING op;
      WHEN 20 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.set_withdraw_vesting_route_operation)', namespace, proc) USING op;
      WHEN 21 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.limit_order_create2_operation)', namespace, proc) USING op;
      WHEN 22 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.claim_account_operation)', namespace, proc) USING op;
      WHEN 23 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.create_claimed_account_operation)', namespace, proc) USING op;
      WHEN 24 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.request_account_recovery_operation)', namespace, proc) USING op;
      WHEN 25 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.recover_account_operation)', namespace, proc) USING op;
      WHEN 26 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.change_recovery_account_operation)', namespace, proc) USING op;
      WHEN 27 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.escrow_transfer_operation)', namespace, proc) USING op;
      WHEN 28 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.escrow_dispute_operation)', namespace, proc) USING op;
      WHEN 29 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.escrow_release_operation)', namespace, proc) USING op;
      WHEN 30 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.pow2_operation)', namespace, proc) USING op;
      WHEN 31 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.escrow_approve_operation)', namespace, proc) USING op;
      WHEN 32 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.transfer_to_savings_operation)', namespace, proc) USING op;
      WHEN 33 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.transfer_from_savings_operation)', namespace, proc) USING op;
      WHEN 34 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.cancel_transfer_from_savings_operation)', namespace, proc) USING op;
      WHEN 35 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.custom_binary_operation)', namespace, proc) USING op;
      WHEN 36 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.decline_voting_rights_operation)', namespace, proc) USING op;
      WHEN 37 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.reset_account_operation)', namespace, proc) USING op;
      WHEN 38 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.set_reset_account_operation)', namespace, proc) USING op;
      WHEN 39 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.claim_reward_balance_operation)', namespace, proc) USING op;
      WHEN 40 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.delegate_vesting_shares_operation)', namespace, proc) USING op;
      WHEN 41 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.account_create_with_delegation_operation)', namespace, proc) USING op;
      WHEN 42 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.witness_set_properties_operation)', namespace, proc) USING op;
      WHEN 43 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.account_update2_operation)', namespace, proc) USING op;
      WHEN 44 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.create_proposal_operation)', namespace, proc) USING op;
      WHEN 45 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.update_proposal_votes_operation)', namespace, proc) USING op;
      WHEN 46 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.remove_proposal_operation)', namespace, proc) USING op;
      WHEN 47 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.update_proposal_operation)', namespace, proc) USING op;
      WHEN 48 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.collateralized_convert_operation)', namespace, proc) USING op;
      WHEN 49 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.recurrent_transfer_operation)', namespace, proc) USING op;
      WHEN 50 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.fill_convert_request_operation)', namespace, proc) USING op;
      WHEN 51 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.author_reward_operation)', namespace, proc) USING op;
      WHEN 52 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.curation_reward_operation)', namespace, proc) USING op;
      WHEN 53 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.comment_reward_operation)', namespace, proc) USING op;
      WHEN 54 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.liquidity_reward_operation)', namespace, proc) USING op;
      WHEN 55 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.interest_operation)', namespace, proc) USING op;
      WHEN 56 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.fill_vesting_withdraw_operation)', namespace, proc) USING op;
      WHEN 57 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.fill_order_operation)', namespace, proc) USING op;
      WHEN 58 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.shutdown_witness_operation)', namespace, proc) USING op;
      WHEN 59 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.fill_transfer_from_savings_operation)', namespace, proc) USING op;
      WHEN 60 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.hardfork_operation)', namespace, proc) USING op;
      WHEN 61 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.comment_payout_update_operation)', namespace, proc) USING op;
      WHEN 62 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.return_vesting_delegation_operation)', namespace, proc) USING op;
      WHEN 63 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.comment_benefactor_reward_operation)', namespace, proc) USING op;
      WHEN 64 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.producer_reward_operation)', namespace, proc) USING op;
      WHEN 65 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.clear_null_account_balance_operation)', namespace, proc) USING op;
      WHEN 66 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.proposal_pay_operation)', namespace, proc) USING op;
      WHEN 67 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.dhf_funding_operation)', namespace, proc) USING op;
      WHEN 68 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.hardfork_hive_operation)', namespace, proc) USING op;
      WHEN 69 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.hardfork_hive_restore_operation)', namespace, proc) USING op;
      WHEN 70 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.delayed_voting_operation)', namespace, proc) USING op;
      WHEN 71 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.consolidate_treasury_balance_operation)', namespace, proc) USING op;
      WHEN 72 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.effective_comment_vote_operation)', namespace, proc) USING op;
      WHEN 73 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.ineffective_delete_comment_operation)', namespace, proc) USING op;
      WHEN 74 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.dhf_conversion_operation)', namespace, proc) USING op;
      WHEN 75 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.expired_account_notification_operation)', namespace, proc) USING op;
      WHEN 76 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.changed_recovery_account_operation)', namespace, proc) USING op;
      WHEN 77 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.transfer_to_vesting_completed_operation)', namespace, proc) USING op;
      WHEN 78 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.pow_reward_operation)', namespace, proc) USING op;
      WHEN 79 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.vesting_shares_split_operation)', namespace, proc) USING op;
      WHEN 80 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.account_created_operation)', namespace, proc) USING op;
      WHEN 81 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.fill_collateralized_convert_request_operation)', namespace, proc) USING op;
      WHEN 82 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.system_warning_operation)', namespace, proc) USING op;
      WHEN 83 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.fill_recurrent_transfer_operation)', namespace, proc) USING op;
      WHEN 84 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.failed_recurrent_transfer_operation)', namespace, proc) USING op;
      WHEN 85 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.limit_order_cancelled_operation)', namespace, proc) USING op;
      WHEN 86 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.producer_missed_operation)', namespace, proc) USING op;
      WHEN 87 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.proposal_fee_operation)', namespace, proc) USING op;
      WHEN 88 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.collateralized_convert_immediate_conversion_operation)', namespace, proc) USING op;
      WHEN 89 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.escrow_approved_operation)', namespace, proc) USING op;
      WHEN 90 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.escrow_rejected_operation)', namespace, proc) USING op;
      WHEN 91 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.proxy_cleared_operation)', namespace, proc) USING op;
      WHEN 92 THEN EXECUTE format('SELECT %I.%I($1, $1.body_binary::hive.declined_voting_rights_operation)', namespace, proc) USING op;
      ELSE RAISE 'Invalid operation type %', op.op_type_id;
    END CASE;
  EXCEPTION
    WHEN undefined_function THEN RETURN;
    WHEN others THEN RAISE;
  END;
END;
$BODY$;

CREATE OR REPLACE FUNCTION hafbe_app.process_block_range_data_a(_from INT, _to INT)
RETURNS VOID
AS
$function$
DECLARE
  __balance_change RECORD;
BEGIN

-- function used to calculate witness votes and proxies
-- updates tables hafbe_app.current_account_proxies, hafbe_app.current_witness_votes, hafbe_app.witness_votes_history, hafbe_app.account_proxies_history
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

    WHEN __balance_change.op_type = 92 OR __balance_change.op_type = 75 THEN
    PERFORM hafbe_app.process_expired_accounts(__balance_change.body);
    

    ELSE
  END CASE;

END LOOP;

PERFORM hafbe_app.process_operation(op, op.op_type_id, 'hafbe_app', 'process_vote_op')
FROM hive.hafbe_app_operations_view AS op
WHERE op.op_type_id = 12 AND op.block_num BETWEEN _from AND _to;

PERFORM hafbe_app.process_operation(op, op.op_type_id, 'hafbe_app', 'process_proxy_op')
FROM hive.hafbe_app_operations_view AS op
WHERE op.op_type_id IN (13,91) AND op.block_num BETWEEN _from AND _to;

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

  PERFORM hafbe_app.process_operation(op, op.op_type_id, 'hafbe_app', 'add_new_witness')
  FROM hive.hafbe_app_operations_view AS op
  WHERE op.op_type_id IN (12,42,11,7) AND op.block_num BETWEEN _from AND _to;

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
  PERFORM hafbe_app.process_operation(op, op.op_type_id, 'hafbe_app', 'parse_witness_url')
  FROM hafbe_views.witness_prop_op_view AS op
  WHERE op.op_type_id IN (42,11) AND op.block_num BETWEEN _from AND _to;

  -- parse witness exchange_rate
  PERFORM hafbe_app.process_operation(op, op.op_type_id, 'hafbe_app', 'parse_witness_exchange_rate')
  FROM hafbe_views.witness_prop_op_view AS op
  WHERE op.op_type_id IN (42,7) AND op.block_num BETWEEN _from AND _to;

  -- parse witness block_size
  PERFORM hafbe_app.process_operation(op, op.op_type_id, 'hafbe_app', 'parse_witness_block_size')
  FROM hafbe_views.witness_prop_op_view AS op
  WHERE op.op_type_id IN (42,11,30,14) AND op.block_num BETWEEN _from AND _to;

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
SET cursor_tuple_fraction = '0.9';


CREATE OR REPLACE FUNCTION hafbe_app.process_block_range_data_c(_from INT, _to INT)
RETURNS VOID
AS
$function$
DECLARE
  __balance_change RECORD;
BEGIN
-- function used for calculating witnesses
-- updates tables hafbe_app.account_posts, hafbe_app.account_parameters

SET ENABLE_NESTLOOP TO FALSE; --TODO: Temporary patch, remove later!!!!!!!!!

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
WHERE 
  (cao.op_type_id IN (9, 23, 41, 80, 76, 25, 36)
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
    o.body-> 'value'->> 'author' AS author,
    o.body-> 'value'->> 'permlink' AS permlink,
    o.block_num,
    o.id
  FROM 
    hive.hafbe_app_operations_view o
  WHERE 
    o.op_type_id =17;

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
