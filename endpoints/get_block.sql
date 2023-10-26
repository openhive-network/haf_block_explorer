SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_head_block_num()
RETURNS INT
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
RETURN num FROM hive.blocks_view ORDER BY num DESC LIMIT 1
;

END
$$
;

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_block(_block_num INT)
RETURNS hafbe_types.block
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
AS
$$
BEGIN
RETURN (
SELECT ROW(
  b.num,   
  b.hash,
  b.prev,
  a.name::TEXT,
  b.transaction_merkle_root,
  b.extensions,
  b.witness_signature,
  b.signing_key,
  b.hbd_interest_rate::numeric,
  b.total_vesting_fund_hive::numeric,
  b.total_vesting_shares::numeric,
  b.total_reward_fund_hive::numeric,
  b.virtual_supply::numeric,
  b.current_supply::numeric,
  b.current_hbd_supply::numeric,
  b.dhf_interval_ledger::numeric,
  b.created_at,
  NOW() - b.created_at)
FROM hive.blocks_view b
JOIN hive.accounts_view a ON a.id = b.producer_account_id
WHERE num = _block_num
);

END
$$
;

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_block_by_time(_timestamp TIMESTAMP)
RETURNS INT
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
RETURN o.num
FROM hive.blocks_view o WHERE o.created_at BETWEEN _timestamp - interval '2 seconds' AND _timestamp ORDER BY o.created_at LIMIT 1
;

END
$$
;

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_latest_blocks(_limit INT = 10)
RETURNS SETOF hafbe_types.get_latest_blocks
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
AS
$$
BEGIN
RETURN QUERY
  WITH select_block_range AS MATERIALIZED (
    SELECT 
      o.num as block_num,
      a.name::TEXT as witness
    FROM hive.blocks_view o
    JOIN hive.accounts_view a ON a.id = o.producer_account_id
    ORDER BY o.num DESC LIMIT _limit
  ),
  join_operations AS MATERIALIZED (
    SELECT 
      s.block_num, 
      s.witness, 
      COUNT(b.op_type_id) as count, 
      b.op_type_id 
    FROM hive.operations_view b
    JOIN select_block_range s ON s.block_num = b.block_num
    GROUP BY b.op_type_id,s.block_num,s.witness
  )
    SELECT block_num, witness, json_agg(json_build_object(
      'count', count,
      'op_type_id', op_type_id
    )) FROM join_operations
    GROUP BY block_num, witness
    ORDER BY block_num DESC
;

END
$$                            
;

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_block_by_op(_operations INT[], _account TEXT = NULL, _order_is hafbe_types.order_is = 'desc', _from INT = 0, _to INT = 2147483647, _limit INT = 100, _key_content TEXT = NULL, VARIADIC _set_key TEXT[] = ARRAY[NULL])
RETURNS SETOF INT
LANGUAGE 'plpgsql' STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
SET enable_sort = OFF
SET enable_hashagg = OFF
AS
$$
BEGIN
IF _account IS NULL THEN

RETURN QUERY (

  WITH selected_range AS (
  SELECT o.block_num FROM hive.operations_view o
  WHERE 
    o.op_type_id = ANY(_operations) AND 
    o.block_num BETWEEN _from AND _to AND 
  (CASE WHEN _key_content IS NOT NULL THEN
    jsonb_extract_path_text(o.body, variadic _set_key) = _key_content
  ELSE
    TRUE
  END)
  ORDER BY
    (CASE WHEN _order_is = 'desc' THEN o.block_num ELSE NULL END) DESC,
    (CASE WHEN _order_is = 'asc' THEN o.block_num ELSE NULL END) ASC
  LIMIT 1000)

  SELECT DISTINCT ON (o.block_num) o.block_num 
  FROM selected_range o
  LIMIT _limit
  );
  
ELSE

RETURN QUERY (

  WITH source_account_id as MATERIALIZED (
  SELECT a.id from hive.accounts_view a where a.name = _account),

  source_ops as MATERIALIZED (
  SELECT ao.operation_id
  FROM hive.account_operations_view ao
  WHERE 
    ao.op_type_id = ANY(_operations) AND 
    ao.account_id = (SELECT id FROM source_account_id) AND 
    ao.block_num BETWEEN _from AND _to
  ORDER BY
    (CASE WHEN _order_is = 'desc' THEN ao.account_op_seq_no ELSE NULL END) DESC,
    (CASE WHEN _order_is = 'asc' THEN ao.account_op_seq_no ELSE NULL END) ASC
  LIMIT _limit)

  SELECT o.block_num
  FROM hive.operations_view o
  JOIN source_ops s on s.operation_id = o.id
  WHERE (CASE WHEN _key_content IS NOT NULL THEN
    jsonb_extract_path_text(o.body, variadic _set_key) = _key_content
  ELSE
    TRUE
  END)
  ORDER BY
    (CASE WHEN _order_is = 'desc' THEN o.block_num ELSE NULL END) DESC,
    (CASE WHEN _order_is = 'asc' THEN o.block_num ELSE NULL END) ASC
  );
  
END IF;
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_backend.get_block_by_op(_operations INT[], _account TEXT = NULL, _order_is hafbe_types.order_is = 'desc', _from INT = 0, _to INT = 2147483647, _limit INT = 100, _key_content TEXT = NULL, VARIADIC _set_key TEXT[] = ARRAY[NULL])
RETURNS SETOF INT[]
LANGUAGE 'plpgsql' STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
SET enable_sort = OFF
SET enable_hashagg = OFF
AS
$$
BEGIN
IF _account IS NULL THEN

RETURN QUERY (

  SELECT array_agg(o.block_num) FROM hive.operations_view o
  WHERE 
    o.op_type_id = ANY(_operations) AND 
    o.block_num BETWEEN _from AND _to AND 
  (CASE WHEN _key_content IS NOT NULL THEN
    jsonb_extract_path_text(o.body, variadic _set_key) = _key_content
  ELSE
    TRUE
  END)
  GROUP BY o.block_num
  ORDER BY
    (CASE WHEN _order_is = 'desc' THEN o.block_num ELSE NULL END) DESC,
    (CASE WHEN _order_is = 'asc' THEN o.block_num ELSE NULL END) ASC
  LIMIT _limit

  );
  
ELSE

RETURN QUERY (

  WITH source_account_id as MATERIALIZED (
  SELECT a.id from hive.accounts_view a where a.name = _account),

  source_ops as MATERIALIZED (
  SELECT ao.operation_id
  FROM hive.account_operations_view ao
  WHERE 
    ao.op_type_id = ANY(_operations) AND 
    ao.account_id = (SELECT id FROM source_account_id) AND 
    ao.block_num BETWEEN _from AND _to
  ORDER BY
    (CASE WHEN _order_is = 'desc' THEN ao.account_op_seq_no ELSE NULL END) DESC,
    (CASE WHEN _order_is = 'asc' THEN ao.account_op_seq_no ELSE NULL END) ASC
  LIMIT _limit)

  SELECT array_agg(o.block_num)
  FROM hive.operations_view o
  JOIN source_ops s on s.operation_id = o.id
  WHERE (CASE WHEN _key_content IS NOT NULL THEN
    jsonb_extract_path_text(o.body, variadic _set_key) = _key_content
  ELSE
    TRUE
  END)
  GROUP BY o.block_num
  ORDER BY
    (CASE WHEN _order_is = 'desc' THEN o.block_num ELSE NULL END) DESC,
    (CASE WHEN _order_is = 'asc' THEN o.block_num ELSE NULL END) ASC
  );
END
$$
;



RESET ROLE;
