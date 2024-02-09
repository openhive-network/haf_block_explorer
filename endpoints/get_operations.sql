SET ROLE hafbe_owner;

/*

SELECT * FROM hafbe_endpoints.get_ops_by_account('anyx') 
-- main page 0,4s

SELECT * FROM hafbe_endpoints.get_ops_by_account('abit', NULL, 100, ARRAY[0,1,2,52,76,53,23]) 
--  with filtered ops 1,06s

SELECT * FROM hafbe_endpoints.get_ops_by_account('blocktrades', NULL, 100, ARRAY[0,1,2,52,76,53,23], 70000000, 71000000) 
--  with filtered ops and blocks 1,08s

SELECT * FROM hafbe_endpoints.get_ops_by_account('blocktrades', NULL, 100 , NULL, 70000000, 71000000) 
--  with only filtered blocks 1,4s

*/

-- Account page and account history endpoint
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_ops_by_account(
    _account TEXT,
    _page_num INT = NULL,
    _page_size INT = 100,
    _filter INT [] = NULL,
    _from INT = NULL,
    _to INT = NULL,
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
-- force_custom_plan added to every function that uses OFFSET
AS
$$
BEGIN
IF _date_start IS NOT NULL THEN
  _from := (SELECT num FROM hive.blocks_view bv WHERE bv.created_at >= _date_start ORDER BY created_at ASC LIMIT 1);
END IF;
IF _date_end IS NOT NULL THEN  
  _to := (SELECT num FROM hive.blocks_view bv WHERE bv.created_at < _date_end ORDER BY created_at DESC LIMIT 1);
END IF;

RETURN (
  WITH ops_count AS MATERIALIZED (
    SELECT * FROM hafbe_backend.get_account_operations_count(_filter, _account, _from, _to)
  ),
  calculate_total_pages AS MATERIALIZED (
    SELECT (CASE WHEN ((SELECT * FROM ops_count) % _page_size) = 0 THEN 
    (SELECT * FROM ops_count)/_page_size ELSE (((SELECT * FROM ops_count)/_page_size) + 1) END)
  )

  SELECT json_build_object(
-- ops_count returns number of operations found with current filter
    'total_operations', (SELECT * FROM ops_count),
-- to count total_pages we need to check if there was a rest from division by _page_size, if there was the page count is +1 
    'total_pages', (SELECT * FROM calculate_total_pages),
    'operations_result', 
    (SELECT to_json(array_agg(row)) FROM (
      SELECT * FROM hafbe_backend.get_ops_by_account(_account, 
-- there is two diffrent page_nums, internal and external, internal page_num is ascending (first page with the newest operation is number 1)
-- external page_num is descending, its given by FE and recalculated by this query to internal 

-- to show the first page on account_page on FE we take page_num as NULL, because FE on the first use of the endpoint doesn't know the ops_count
-- For example query returns 15 pages and FE asks for:
-- page 15 (external first page) 15 - 15 + 1 = 1 (internal first page)
-- page 14 (external second page) 15 - 14 + 1 = 2 (internal second page)
-- ... page 7, 15 - 7 + 1 =  9 (internal 9th page)
      (CASE WHEN _page_num IS NULL THEN 1 ELSE (((SELECT * FROM calculate_total_pages) - _page_num) + 1) END)::INT,
      _page_size,
      _filter,
      _from,
      _to,
      _body_limit,
       ((SELECT * FROM ops_count) % _page_size)::INT,
       (SELECT * FROM ops_count)::INT)

-- to return the first page with the rest of the division of ops count the number is handed over to backend function
    ) row)
  ));

END
$$;

-- Block page endpoint
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_ops_by_block_paging(
    _block_num INT,
    _page_num INT = 1,
    _page_size INT = 100,
    _filter SMALLINT [] = NULL,
    _order_is hafbe_types.order_is = 'desc', -- noqa: LT01, CP05
    _body_limit INT = 2147483647
)
RETURNS JSON -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
SET JIT = OFF
SET join_collapse_limit = 16
SET from_collapse_limit = 16
AS
$$
BEGIN
RETURN (
  WITH ops_count AS MATERIALIZED (
    SELECT * FROM hafbe_backend.get_ops_by_block_count(_block_num, _filter)
  ),
  calculate_total_pages AS MATERIALIZED (
    SELECT 
      (CASE 
        WHEN ((SELECT * FROM ops_count) % _page_size) = 0 THEN 
          (SELECT * FROM ops_count)/_page_size 
        ELSE 
          (((SELECT * FROM ops_count)/_page_size) + 1) END)
  )
  SELECT json_build_object(
    'total_operations', (SELECT * FROM ops_count),
    'total_pages', (SELECT * FROM calculate_total_pages),
    'operations_result', 
    (SELECT to_json(array_agg(row)) FROM (
      SELECT * FROM hafbe_backend.get_ops_by_block(
      _block_num, 
      _page_num,
      _page_size,
      _filter,
      _order_is,
      _body_limit)
    ) row)
  ));

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
      ov.id,
      ov.block_num,
      ov.trx_in_block,
      encode(htv.trx_hash, 'hex'),
      ov.op_pos,
      ov.op_type_id,
      ov.body,
      hot.is_virtual,
      ov.timestamp,
      NOW() - ov.timestamp,
  	  FALSE)
    FROM hive.operations_view ov 
    JOIN hive.operation_types hot ON hot.id = ov.op_type_id
    LEFT JOIN hive.transactions_view htv ON htv.block_num = ov.block_num AND htv.trx_in_block = ov.trx_in_block
	  WHERE ov.id = _operation_id
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
	_example_key JSON := (SELECT ov.body FROM hive.operations_view ov WHERE ov.op_type_id = _op_type_id LIMIT 1);
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
    _operation_types INT [] = ARRAY[0, 1, 17, 19, 51, 52, 53, 61, 63, 72, 73],
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
  allowed_ids INT[] := ARRAY[0, 1, 17, 19, 51, 52, 53, 61, 63, 72, 73];
BEGIN
IF NOT _operation_types <@ allowed_ids THEN
    RAISE EXCEPTION 'Invalid operation ID detected. Allowed IDs are: %', allowed_ids;
END IF;

IF _start_date IS NOT NULL THEN
  _from := (SELECT num FROM hive.blocks_view bv WHERE bv.created_at >= _start_date ORDER BY created_at ASC LIMIT 1);
END IF;
IF _end_date IS NOT NULL THEN  
  _to := (SELECT num FROM hive.blocks_view bv WHERE bv.created_at < _end_date ORDER BY created_at DESC LIMIT 1);
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
