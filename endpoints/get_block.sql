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

CREATE OR REPLACE FUNCTION hafbe_backend.get_block_by_op(_operations INT[], _account TEXT = NULL, _order_is hafbe_types.order_is = 'desc',
 _from INT = 0, _to INT = 2147483647, _limit INT = 100, _key_content TEXT = NULL, _set_key TEXT[] = ARRAY[NULL])
RETURNS SETOF hafbe_types.get_block_by_ops
LANGUAGE 'plpgsql' STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
SET enable_hashagg = OFF
AS
$$
DECLARE 
	__operations INT[] := (SELECT array_agg(elem+1) FROM unnest(_operations) AS elem);
BEGIN

IF _key_content IS NOT NULL THEN
  IF array_length(_operations, 1) != 1 THEN 
    RAISE EXCEPTION 'Invalid set of operations, use single operation. ';
  END IF;
  
  IF NOT _set_key = ANY(SELECT * FROM hafbe_endpoints.get_operation_keys((SELECT unnest(_operations)))) THEN
    RAISE EXCEPTION 'Invalid key: %. ', _set_key;
  END IF;
END IF;

IF _account IS NULL THEN

  IF _key_content IS NULL THEN
  RETURN QUERY EXECUTE format(
	  $query$
    WITH source_ops AS MATERIALIZED (
    SELECT o.block_num, array_agg(o.op_type_id) as op_type_id FROM hive.operations_view o
    WHERE 
      o.op_type_id + 1 = ANY(%L) AND 
-- o.op_type_id + 1 is required so the postgresql planner changes index from hive_operations_op_type_id_block_num to 
-- hive_operations_block_num_trx_in_block_idx because of perfomance improvement, when using more than one operation.
      o.block_num BETWEEN %L AND %L 
    GROUP BY o.block_num
    ORDER BY o.block_num %s
    LIMIT %L)
    SELECT block_num, ARRAY(SELECT DISTINCT unnest(op_type_id)) as op_type_id
    FROM source_ops;
  	$query$, 

	__operations, _from, _to, _order_is, _limit) res
  ;

  ELSE 
  RETURN QUERY EXECUTE format(
	  $query$
    WITH source_ops AS MATERIALIZED (
    SELECT o.block_num, array_agg(o.op_type_id) as op_type_id FROM hive.operations_view o
    WHERE 
      o.op_type_id = ANY(%L) AND 
      o.block_num BETWEEN %L AND %L AND 
      jsonb_extract_path_text(o.body, variadic %L) = %L
    GROUP BY o.block_num
    ORDER BY o.block_num %s
    LIMIT %L)
    SELECT block_num, ARRAY(SELECT DISTINCT unnest(op_type_id)) as op_type_id
    FROM source_ops;
  	$query$, 

	_operations, _from, _to, _set_key, _key_content, _order_is, _limit) res
  ;
  
  END IF;
ELSE

  IF _key_content IS NULL THEN
  RETURN QUERY EXECUTE format(
    $query$
    WITH source_account_id AS MATERIALIZED (
    SELECT a.id from hive.accounts_view a where a.name = %L),

    source_ops AS MATERIALIZED (
    SELECT array_agg(ao.op_type_id) AS op_type_id, ao.block_num
    FROM hive.account_operations_view ao
    WHERE 
      ao.op_type_id = ANY(%L) AND 
      ao.account_id = (SELECT id FROM source_account_id) AND 
      ao.block_num BETWEEN %L AND %L
    GROUP BY ao.block_num
    ORDER BY ao.block_num %s
    LIMIT %L)

    SELECT block_num, ARRAY(SELECT DISTINCT unnest(op_type_id)) as op_type_id
    FROM source_ops
    ORDER BY block_num %s
    ;
    $query$, 

  _account, _operations, _from, _to, _order_is, _limit, _order_is)
  ;

  ELSE
  RETURN QUERY EXECUTE format(
    $query$
    WITH source_account_id AS MATERIALIZED (
    SELECT a.id from hive.accounts_view a where a.name = %L),

    source_ops AS (
    SELECT array_agg(ao.operation_id) AS operation_id, ao.block_num
    FROM hive.account_operations_view ao
    WHERE 
      ao.op_type_id = ANY(%L) AND 
      ao.account_id = (SELECT id FROM source_account_id) AND 
      ao.block_num BETWEEN %L AND %L
    GROUP BY ao.block_num
    ORDER BY ao.block_num %s),  

    source_ops_agg AS (
    SELECT o.block_num, array_agg(o.op_type_id) as op_type_id
    FROM hive.operations_view o
    JOIN (
    SELECT unnest(operation_id) AS operation_id
    FROM source_ops
    ) s on s.operation_id = o.id
    WHERE 
      jsonb_extract_path_text(o.body, variadic %L) = %L AND
      o.op_type_id = ANY(%L)
    GROUP BY o.block_num)

    SELECT block_num, ARRAY(SELECT DISTINCT unnest(op_type_id)) as op_type_id
    FROM source_ops_agg
    ORDER BY block_num %s
    LIMIT %L
    $query$, 

  _account, _operations, _from, _to, _order_is, _set_key, _key_content, _operations, _order_is, _limit)
  ;

  END IF;
END IF;
END
$$
;




RESET ROLE;
