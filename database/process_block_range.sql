SET ROLE hafbe_owner;

DROP FUNCTION IF EXISTS hafbe_app.process_operation_range;
CREATE OR REPLACE FUNCTION hafbe_app.process_operation_range(
  namespace TEXT,
  proc TEXT,
  _from INT,
  _to INT
)
RETURNS void
LANGUAGE plpgsql
VOLATILE
AS $BODY$
DECLARE
  op RECORD;
BEGIN
  FOR op IN
    SELECT o.*, o.id AS operation_id
      FROM pg_proc AS p
      JOIN pg_type AS t ON p.proargtypes[1] = t.oid
      JOIN pg_namespace AS ns ON p.pronamespace = ns.oid
      JOIN hive.operation_types AS ot ON split_part(ot.name, '::', 3) = t.typname
      JOIN hive.hafbe_app_operations_view AS o ON o.op_type_id = ot.id
      WHERE p.proname = proc AND ns.nspname = namespace AND o.block_num BETWEEN _from and _to
      ORDER BY o.block_num ASC
  LOOP
    CASE op.op_type_id OF
      WHEN 0 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.vote_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 1 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.comment_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 2 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.transfer_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 3 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.transfer_to_vesting_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 4 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.withdraw_vesting_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 5 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.limit_order_create_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 6 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.limit_order_cancel_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 7 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.feed_publish_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 8 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.convert_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 9 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.account_create_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 10 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.account_update_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 11 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.witness_update_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 12 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.account_witness_vote_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 13 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.account_witness_proxy_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 14 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.pow_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 15 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.custom_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 16 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.witness_block_approve_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 17 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.delete_comment_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 18 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.custom_json_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 19 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.comment_options_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 20 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.set_withdraw_vesting_route_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 21 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.limit_order_create2_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 22 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.claim_account_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 23 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.create_claimed_account_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 24 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.request_account_recovery_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 25 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.recover_account_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 26 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.change_recovery_account_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 27 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.escrow_transfer_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 28 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.escrow_dispute_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 29 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.escrow_release_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 30 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.pow2_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 31 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.escrow_approve_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 32 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.transfer_to_savings_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 33 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.transfer_from_savings_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 34 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.cancel_transfer_from_savings_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 35 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.custom_binary_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 36 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.decline_voting_rights_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 37 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.reset_account_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 38 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.set_reset_account_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 39 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.claim_reward_balance_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 40 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.delegate_vesting_shares_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 41 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.account_create_with_delegation_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 42 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.witness_set_properties_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 43 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.account_update2_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 44 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.create_proposal_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 45 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.update_proposal_votes_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 46 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.remove_proposal_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 47 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.update_proposal_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 48 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.collateralized_convert_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 49 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.recurrent_transfer_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 50 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.fill_convert_request_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 51 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.author_reward_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 52 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.curation_reward_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 53 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.comment_reward_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 54 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.liquidity_reward_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 55 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.interest_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 56 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.fill_vesting_withdraw_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 57 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.fill_order_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 58 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.shutdown_witness_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 59 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.fill_transfer_from_savings_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 60 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.hardfork_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 61 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.comment_payout_update_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 62 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.return_vesting_delegation_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 63 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.comment_benefactor_reward_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 64 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.producer_reward_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 65 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.clear_null_account_balance_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 66 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.proposal_pay_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 67 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.dhf_funding_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 68 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.hardfork_hive_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 69 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.hardfork_hive_restore_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 70 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.delayed_voting_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 71 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.consolidate_treasury_balance_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 72 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.effective_comment_vote_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 73 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.ineffective_delete_comment_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 74 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.dhf_conversion_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 75 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.expired_account_notification_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 76 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.changed_recovery_account_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 77 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.transfer_to_vesting_completed_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 78 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.pow_reward_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 79 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.vesting_shares_split_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 80 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.account_created_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 81 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.fill_collateralized_convert_request_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 82 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.system_warning_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 83 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.fill_recurrent_transfer_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 84 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.failed_recurrent_transfer_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 85 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.limit_order_cancelled_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 86 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.producer_missed_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 87 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.proposal_fee_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 88 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.collateralized_convert_immediate_conversion_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 89 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.escrow_approved_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 90 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.escrow_rejected_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 91 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.proxy_cleared_operation)', namespace, proc) USING op.body_binary, op;
      WHEN 92 THEN EXECUTE format('SELECT %I.%I($2, $1::hive.declined_voting_rights_operation)', namespace, proc) USING op.body_binary, op;
      ELSE RAISE 'Invalid operation type %', op.op_type_id;
    END CASE;
  END LOOP;
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

    WHEN __balance_change.op_type = 13 OR __balance_change.op_type = 91 THEN
    PERFORM hafbe_app.process_proxy_ops(__balance_change.body, __balance_change.timestamp, __balance_change.op_type);

    WHEN __balance_change.op_type = 92 OR __balance_change.op_type = 75 THEN
    PERFORM hafbe_app.process_expired_accounts(__balance_change.body);
    

    ELSE
  END CASE;

END LOOP;

PERFORM hafbe_app.process_operation_range('hafbe_app', 'process_vote_op', _from, _to);

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
  SELECT av.id, NULL, NULL, NULL, NULL, NULL, NULL, NULL
  FROM select_witness_names swn
  JOIN hive.hafbe_app_accounts_view av ON av.name = swn.name
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
    SELECT av.id AS witness_id, url
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
    JOIN hive.accounts_view av ON av.name = prop.witness
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
      av.id AS witness_id,
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
    JOIN hive.accounts_view av ON av.name = prop.witness
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
    SELECT av.id AS witness_id, block_size
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
    JOIN hive.accounts_view av ON av.name = prop.witness
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
    SELECT av.id AS witness_id, signing_key
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
    JOIN hive.accounts_view av ON av.name = prop.witness
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
    ov.body AS body,
    ov.id AS source_op,
    ov.block_num AS source_op_block,
    ov.timestamp AS _timestamp,
    ov.op_type_id AS op_type
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
