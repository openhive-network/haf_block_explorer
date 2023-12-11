SET ROLE hafbe_owner;

-- Account page and account history endpoint
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_ops_by_account(
    _account TEXT,
    _page_num INT = 1,
    _page_size INT = 100,
    _filter SMALLINT [] = NULL,
    _date_start TIMESTAMP = NULL,
    _date_end TIMESTAMP = NULL,
    _body_limit INT = 2147483647
)
RETURNS JSON -- 'total_operations, total_pages, operations_result'
LANGUAGE 'plpgsql' STABLE
SET join_collapse_limit = 16
SET from_collapse_limit = 16
SET JIT = OFF
SET enable_hashjoin = OFF
SET plan_cache_mode = force_custom_plan
AS
$$
BEGIN
RETURN (
  WITH ops_count AS MATERIALIZED (
    SELECT * FROM hafbe_backend.get_account_operations_count(_filter, _account)
  )

  SELECT json_build_object(
    'total_operations', (SELECT * FROM ops_count),
    'total_pages', (SELECT * FROM ops_count)/100,
    'operations_result', 
    (SELECT to_json(array_agg(row)) FROM (
      SELECT * FROM hafbe_backend.get_ops_by_account(_account, _page_num, _page_size, _filter, _date_start, _date_end, _body_limit)
    ) row)
  ));

END
$$;

-- Block page endpoint
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_ops_by_block(
    _block_num INT,
    _top_op_id BIGINT = 9223372036854775807,
    _limit INT = 1000,
    _filter SMALLINT [] = ARRAY[]::SMALLINT [],
    _body_limit INT = 2147483647
)
RETURNS SETOF hafbe_types.operation -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
SET JIT = OFF
SET join_collapse_limit = 16
SET from_collapse_limit = 16
AS
$$
DECLARE
  __no_ops_filter BOOLEAN = ((SELECT array_length(_filter, 1)) IS NULL);
BEGIN
RETURN QUERY 
WITH operation_range AS MATERIALIZED (
  SELECT
    ls.id,
    ls.block_num,
    ls.trx_in_block,
    encode(htv.trx_hash, 'hex') AS trx_hash,
    ls.op_pos,
    ls.op_type_id,
    ls.body,
    hot.is_virtual,
    ls.timestamp,
    NOW() - ls.timestamp AS age
  FROM (
    SELECT hov.id, hov.trx_in_block, hov.op_pos, hov.timestamp, hov.body, hov.op_type_id, hov.block_num
    FROM hive.operations_view hov
    WHERE
      hov.block_num = _block_num AND
      hov.id <= _top_op_id AND 
      (__no_ops_filter OR hov.op_type_id = ANY(_filter))
    ORDER BY hov.id DESC
    LIMIT _limit
  ) ls
  JOIN hive.operation_types hot ON hot.id = ls.op_type_id
  LEFT JOIN hive.transactions_view htv ON htv.block_num = ls.block_num AND htv.trx_in_block = ls.trx_in_block
  ORDER BY ls.id DESC)

-- filter too long operation bodies 
  SELECT s.id, s.block_num, s.trx_in_block, s.trx_hash, s.op_pos, s.op_type_id, (s.composite).body, s.is_virtual, s.timestamp, s.age, (s.composite).is_modified
  FROM (
  SELECT hafbe_backend.operation_body_filter(o.body, o.id, _body_limit) as composite, o.id, o.block_num, o.trx_in_block, o.trx_hash, o.op_pos, o.op_type_id, o.is_virtual, o.timestamp, o.age
  FROM operation_range o 
  ) s
  ORDER BY s.id;

END
$$;

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_operation(_operation_id INT)
RETURNS hafbe_types.operation -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
RETURN (
  SELECT ROW (
      o.id,
      o.block_num,
      o.trx_in_block,
      encode(htv.trx_hash, 'hex'),
      o.op_pos,
      o.op_type_id,
      o.body,
      hot.is_virtual,
      o.timestamp,
      NOW() - o.timestamp,
  	  FALSE)
    FROM hive.operations_view o 
    JOIN hive.operation_types hot ON hot.id = o.op_type_id
    LEFT JOIN hive.transactions_view htv ON htv.block_num = o.block_num AND htv.trx_in_block = o.trx_in_block
	  WHERE o.id = _operation_id
);

END
$$;

-- Block search endpoint
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_operation_keys(_op_type_id INT)
RETURNS SETOF TEXT []
LANGUAGE 'plpgsql' STABLE
SET JIT = OFF
SET join_collapse_limit = 16
SET from_collapse_limit = 16
SET enable_bitmapscan = OFF
-- enable_bitmapscan = OFF helps with perfomance on database with smaller number of blocks 
-- (tested od 12m blocks, planner choses wrong plan and the query is slow)
AS
$$
DECLARE
	_example_key JSON := (SELECT o.body FROM hive.operations_view o WHERE o.op_type_id = _op_type_id LIMIT 1);
BEGIN
RETURN QUERY
WITH RECURSIVE extract_keys AS (
  SELECT 
    ARRAY['value']::TEXT[] as key_path, 
    (json_each(_example_key -> 'value')).*
  UNION ALL
  SELECT 
    key_path || key,
    (json_each(value)).*
  FROM 
    extract_keys
  WHERE 
    json_typeof(value) = 'object'
)
SELECT 
  key_path || key as full_key_path
FROM 
  extract_keys
WHERE 
  json_typeof(value) != 'object'
;

END
$$;

-- Comment history endpoint
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_comment_operations(
    _author TEXT,
    _permlink TEXT = NULL,
    _page_num INT = 1,
    _page_size INT = 100,
    _operation_types INT [] = ARRAY[0, 1, 17, 19, 51, 53, 61, 63, 72, 73],
    _from INT = 0,
    _to INT = 2147483647,
    _start_date TIMESTAMP = NULL,
    _end_date TIMESTAMP = NULL,
    _body_limit INT = 2147483647
)
RETURNS JSON -- 'total_operations, total_pages, operations_result'
LANGUAGE 'plpgsql' STABLE
SET join_collapse_limit = 16
SET from_collapse_limit = 16
SET JIT = OFF
SET enable_hashjoin = OFF
SET plan_cache_mode = force_custom_plan
AS
$$
DECLARE
  allowed_ids INT[] := ARRAY[0, 1, 17, 19, 51, 53, 61, 63, 72, 73];
BEGIN
IF NOT _operation_types <@ allowed_ids THEN
    RAISE EXCEPTION 'Invalid operation ID detected. Allowed IDs are: %', allowed_ids;
END IF;

IF _start_date IS NOT NULL THEN
  _from := (SELECT num FROM hive.blocks_view hbv WHERE hbv.created_at >= _start_date ORDER BY created_at ASC LIMIT 1);
END IF;
IF _end_date IS NOT NULL THEN  
  _to := (SELECT num FROM hive.blocks_view hbv WHERE hbv.created_at < _end_date ORDER BY created_at DESC LIMIT 1);
END IF;

RETURN (
  WITH ops_count AS MATERIALIZED (
    SELECT * FROM hafbe_backend.get_comment_operations_count(_author, _permlink, _operation_types, _from, _to)
  )

  SELECT json_build_object(
    'total_operations', (SELECT * FROM ops_count),
    'total_pages', (SELECT * FROM ops_count)/100,
    'operations_result', 
    (SELECT to_json(array_agg(row)) FROM (
      SELECT * FROM hafbe_backend.get_comment_operations(_author, _permlink, _page_num, _page_size, _operation_types, _from, _to, _body_limit)
    ) row)
  ));

END
$$;


RESET ROLE;
