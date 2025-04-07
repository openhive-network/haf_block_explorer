SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_backend.blocksearch_account_key_value(
    _operation INT,
    _account_id INT,
    _from INT, 
    _to INT,
    _order_is hafbe_types.sort_direction, -- noqa: LT01, CP05
    _page INT,
    _limit INT,
    _key_content TEXT [],
    _setof_keys JSON
)
RETURNS hafbe_types.block_history -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
SET plan_cache_mode = force_custom_plan
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET JIT = OFF
AS
$$
DECLARE
  __hafbe_current_block INT := (SELECT current_block_num FROM hafd.contexts WHERE name = 'hafbe_app');
  __max_page_count INT := 10;

  __min_block_num INT;
  __count_pre_grouped_blocks INT;
  __count INT;
  __from INT;
  __to INT;
  __total_pages INT;

  _result hafbe_types.blocksearch[];
  -- keys must be declared in seperate variables
  -- otherwise planner will not use indexes
  _path1 TEXT[] := ARRAY(SELECT json_array_elements_text(_setof_keys->0));
  _path2 TEXT[] := ARRAY(SELECT json_array_elements_text(_setof_keys->1));
  _path3 TEXT[] := ARRAY(SELECT json_array_elements_text(_setof_keys->2));
BEGIN  
  SELECT from_block, to_block
  INTO __from, __to
  FROM hafbe_backend.blocksearch_range(_from, _to, __hafbe_current_block);

  WITH source_ops AS (
    SELECT 
      aov.block_num,
      aov.operation_id,
      aov.op_type_id
    FROM 
      hive.account_operations_view aov
    WHERE 
      aov.op_type_id = _operation AND
      aov.account_id = _account_id AND
      aov.block_num >= __from AND
      aov.block_num <= __to
    ORDER BY
      (CASE WHEN _order_is = 'desc' THEN aov.block_num ELSE NULL END) DESC,
      (CASE WHEN _order_is = 'asc' THEN aov.block_num ELSE NULL END) ASC
  ),
  filter_by_key AS (
    SELECT 
      ov.block_num,
      ov.id
    FROM hive.operations_view ov
    WHERE 
      ov.op_type_id = _operation AND
      ov.block_num >= __from AND
      ov.block_num <= __to AND
      ((_key_content[1] IS NULL) OR jsonb_extract_path_text(ov.body, variadic _path1) = _key_content[1]) AND
      ((_key_content[2] IS NULL) OR jsonb_extract_path_text(ov.body, variadic _path2) = _key_content[2]) AND
      ((_key_content[3] IS NULL) OR jsonb_extract_path_text(ov.body, variadic _path3) = _key_content[3])
    ORDER BY
      (CASE WHEN _order_is = 'desc' THEN ov.block_num ELSE NULL END) DESC,
      (CASE WHEN _order_is = 'asc' THEN ov.block_num ELSE NULL END) ASC
  ),
  gather_operations AS MATERIALIZED (
    SELECT 
      so.block_num,
      so.op_type_id
	  FROM source_ops so
	  JOIN filter_by_key fbk on so.operation_id = fbk.id
    LIMIT (__max_page_count * _limit) -- by default operation filter is limited to 1 page
  ),
  group_by_type_and_block AS (
    SELECT 
      block_num,
      op_type_id,
      COUNT(*) AS op_count
    FROM gather_operations
    GROUP BY block_num, op_type_id
  ),
  eliminate_duplicate_blocks AS MATERIALIZED (
    SELECT 
      block_num,
      hafbe_backend.build_json_for_single_operation(op_type_id, op_count::INT) AS operations
    FROM group_by_type_and_block
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
  count_pre_grouped_blocks AS (
    SELECT 
      COUNT(*) AS count
    FROM gather_operations
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
    (SELECT count FROM count_pre_grouped_blocks),
    (
      SELECT array_agg(rows ORDER BY 
        (CASE WHEN _order_is = 'desc' THEN rows.block_num ELSE NULL END) DESC,
        (CASE WHEN _order_is = 'asc' THEN rows.block_num ELSE NULL END) ASC
      ) FROM (
        SELECT 
          s.block_num,
          s.created_at,
          s.producer_account,
          s.producer_reward,
          s.trx_count,
          s.hash,
          s.prev,
          s.operations
        FROM result_query s
      ) rows
    )
  INTO __count, __total_pages, __min_block_num, __count_pre_grouped_blocks, _result;

  -- 1. If the min block number is NULL - the result is empty - there are no results for whole provided range
  -- 2. If the min block number is NOT NULL and pages are not fully saturated it means there is no more blocks to fetch 
  -- 3. (ELSE) If the min block number is NOT NULL - the result is not empty - there are results for the provided range
  -- and the min block number can be used as filter in the next API call (as a to-block parameter)
  __from := (
    CASE
      WHEN __min_block_num IS NULL THEN __from
      WHEN __min_block_num IS NOT NULL AND __min_block_num = 1 THEN 1
      WHEN __min_block_num IS NOT NULL AND __min_block_num != 1 AND __count_pre_grouped_blocks != __max_page_count * _limit THEN __from
      ELSE __min_block_num - 1
    END
  );

  RETURN (
    COALESCE(__count, 0),
    COALESCE(__total_pages, 0),
    (__from, __to)::hafbe_types.block_range,
    COALESCE(_result, '{}'::hafbe_types.blocksearch[])
  )::hafbe_types.block_history;

END
$$;

RESET ROLE;
