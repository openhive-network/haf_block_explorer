SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_backend.blocksearch_single_op(
    _operation INT,
    _from INT, 
    _to INT,
    _order_is hafbe_types.sort_direction, -- noqa: LT01, CP05
    _page INT,
    _limit INT
)
RETURNS JSON -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET JIT = OFF
AS
$$
DECLARE 
  __hafbe_current_block INT := (SELECT current_block_num FROM hafd.contexts WHERE name = 'hafbe_app');
  __max_page_count INT := 10;

  __min_block_num INT;
  __count INT;
  __from INT;
  __to INT;
  __total_pages INT;

  _result JSON;
BEGIN
  SELECT from_block, to_block
  INTO __from, __to
  FROM hafbe_backend.blocksearch_range(_from, _to, __hafbe_current_block);

  WITH gather_operations AS MATERIALIZED (
    SELECT 
      bo.block_num,
      bo.op_type_id, 
      bo.op_count
    FROM hafbe_app.block_operations bo
    WHERE
      bo.op_type_id = _operation AND
      bo.block_num >= __from AND
      bo.block_num <= __to
    ORDER BY
      (CASE WHEN _order_is = 'desc' THEN bo.block_num ELSE NULL END) DESC,
      (CASE WHEN _order_is = 'asc' THEN bo.block_num ELSE NULL END) ASC
    LIMIT (__max_page_count * _limit)
  ),
  eliminate_duplicate_blocks AS MATERIALIZED (
    SELECT 
      block_num,
      hafbe_backend.build_json_for_single_operation(op_type_id, op_count::INT) AS operations
    FROM gather_operations
  ),
  -----------PAGING LOGIC----------------
  -- Pages are counted differently compared to default.sql
  -- The results are based on a set of blocks for each operation, 
  -- so the count and total number of pages depend on the specific query inside this cte chain
  min_block_num AS (
    SELECT 
      MIN(block_num) AS block_num
    FROM eliminate_duplicate_blocks
  ),
  count_blocks AS MATERIALIZED (
    SELECT 
      COUNT(*) AS count
    FROM eliminate_duplicate_blocks
  ),
  calculate_pages AS MATERIALIZED (
    SELECT 
      total_pages,
      offset_filter,
      limit_filter
    FROM hafbe_backend.blocksearch_calculate_pages(
      (SELECT count FROM count_blocks)::INT,
      _page,
      _order_is,
      _limit
    )
  ),
  filter_page AS MATERIALIZED (
    SELECT 
      block_num,
      operations
    FROM eliminate_duplicate_blocks
    ORDER BY
      (CASE WHEN _order_is = 'desc' THEN block_num ELSE NULL END) DESC,
      (CASE WHEN _order_is = 'asc' THEN block_num ELSE NULL END) ASC
    offset (SELECT offset_filter FROM calculate_pages)
    LIMIT (SELECT limit_filter FROM calculate_pages)
  ),
  ---------------------------------------
  join_blocks AS (
    SELECT 
      bo.block_num,
      bo.operations,
      bv.created_at, 
      bv.producer_account_id,
      bv.hash,
      bv.prev
    FROM filter_page bo
    JOIN hive.blocks_view bv ON bv.num = bo.block_num
  ),
  result_query AS (
    SELECT 
      bo.block_num,
      bo.created_at, 
      hafbe_backend.get_account_name(bo.producer_account_id) AS producer_account,
      hafbe_backend.get_producer_reward(bo.block_num)::TEXT AS producer_reward,
      hafbe_backend.get_trx_count(bo.block_num) AS trx_count,
      encode(bo.hash, 'hex') AS hash,
      encode(bo.prev, 'hex') AS prev,
      bo.operations
    FROM join_blocks bo
  )
  SELECT 
    (SELECT count FROM count_blocks),
    (SELECT total_pages FROM calculate_pages),
    (SELECT block_num FROM min_block_num),
    COALESCE(
      (
        SELECT json_agg(result) FROM (
          SELECT * FROM result_query
        ) AS result
      ), '[]'::json
    )
  INTO __count, __total_pages, __min_block_num, _result;

  -- 1. If the min block number is NULL - the result is empty - there are no results for whole provided range
  -- 2. If the min block number is NOT NULL and pages are not fully saturated it means there is no more blocks to fetch 
  -- 3. (ELSE) If the min block number is NOT NULL - the result is not empty - there are results for the provided range
  -- and the min block number can be used as filter in the next API call (as a to-block parameter)
  __from := (
    CASE
      WHEN __min_block_num IS NULL THEN __from
      WHEN __min_block_num IS NOT NULL AND __min_block_num = 1 THEN 1
      WHEN __min_block_num IS NOT NULL AND __min_block_num != 1 AND __count != __max_page_count * _limit THEN __from
      ELSE __min_block_num - 1
    END
  );

  RETURN json_build_object(
    'total_blocks', __count,
    'total_pages', __total_pages,
    'block_range', json_build_object('from', __from, 'to', __to),
    'blocks_result', COALESCE(_result, '[]'::json)
  );

END
$$;

RESET ROLE;
