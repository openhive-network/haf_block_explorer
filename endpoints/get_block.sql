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
$$;

-- Block page endpoint
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_block(_block_num INT)
RETURNS hafbe_types.block -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
SET JIT = OFF
SET join_collapse_limit = 16
SET from_collapse_limit = 16
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
$$;

-- Block page endpoint
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
$$;

-- Home page endpoint used in 'last blocks' section
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_latest_blocks(_limit INT = 10)
RETURNS SETOF hafbe_types.get_latest_blocks -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
SET JIT = OFF
SET join_collapse_limit = 16
SET from_collapse_limit = 16
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
$$;

/*
EXAMPLE USAGES

SELECT * FROM hafbe_endpoints.get_block_by_op(ARRAY[0,2,8,32,84,27,83,23,43,65,29,68], NULL, 'desc', 0, 2147483647, 100)

SELECT * FROM hafbe_endpoints.get_block_by_op(ARRAY[0,2,8,32,84,27,83,23,43,65,29,68], 'gtg',
    'desc', 0, 2147483647, 100)


SELECT * FROM hafbe_endpoints.get_block_by_op(ARRAY[1], 'gtg', 'desc',0, 2147483647, 100, ARRAY['abit'],
    '[["value", "author"]]')

SELECT * FROM hafbe_endpoints.get_block_by_op(ARRAY[1], 'gtg', 'desc',0, 2147483647, 100, ARRAY['blocktrades'],
    '[["value", "author"]]')

SELECT * FROM hafbe_endpoints.get_block_by_op(ARRAY[51], NULL, 'desc', 0, 2147483647, 100, ARRAY['gtg'],
    '[["value", "author"]]')

SELECT * FROM hafbe_endpoints.get_block_by_op(ARRAY[68], NULL, 'desc', 0, 2147483647, 100)
*/

-- Block search endpoint
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_block_by_op(
    _operations INT [],
    _account TEXT = NULL,
    _order_is hafbe_types.order_is = 'desc', -- noqa: LT01, CP05
    _from INT = 0,
    _to INT = 2147483647,
    _start_date TIMESTAMP = NULL,
    _end_date TIMESTAMP = NULL,
    _limit INT = 100,
    _key_content TEXT [] = NULL,
    _setof_keys JSON = NULL
)
RETURNS SETOF hafbe_types.get_block_by_ops -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET plan_cache_mode = force_custom_plan
AS
$$
BEGIN
IF _key_content IS NOT NULL THEN
  IF array_length(_operations, 1) != 1 THEN 
    RAISE EXCEPTION 'Invalid set of operations, use single operation. ';
  END IF;
  
  FOR i IN 0 .. json_array_length(_setof_keys)-1 LOOP
	IF NOT ARRAY(SELECT json_array_elements_text(_setof_keys->i)) = ANY(SELECT * FROM hafbe_endpoints.get_operation_keys((SELECT unnest(_operations)))) THEN
	  RAISE EXCEPTION 'Invalid key %', _setof_keys->i;
    END IF;
  END LOOP;
END IF;

IF _start_date IS NOT NULL THEN
  _from := (SELECT num FROM hive.blocks_view hbv WHERE hbv.created_at >= _start_date ORDER BY created_at ASC LIMIT 1);
END IF;
IF _end_date IS NOT NULL THEN  
  _to := (SELECT num FROM hive.blocks_view hbv WHERE hbv.created_at < _end_date ORDER BY created_at DESC LIMIT 1);
END IF;

IF array_length(_operations, 1) = 1 THEN
  RETURN QUERY 
      SELECT * FROM hafbe_backend.get_block_by_single_op(_operations[1], _account, _order_is, _from, _to, _limit, _key_content, _setof_keys)
  ;

ELSE
  RETURN QUERY
      SELECT * FROM hafbe_backend.get_block_by_ops_group_by_block_num(_operations, _account, _order_is, _from, _to, _limit)
  ;

END IF;
END
$$;

RESET ROLE;
