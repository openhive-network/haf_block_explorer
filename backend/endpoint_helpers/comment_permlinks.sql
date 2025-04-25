SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_backend.get_comment_permlinks(
    _author TEXT,
    _comment_type hafbe_types.comment_type,
    _page INT,
    _page_size INT,
    _from INT,
    _to INT
)
RETURNS hafbe_types.permlink_history
LANGUAGE 'plpgsql' STABLE
SET join_collapse_limit = 16
SET from_collapse_limit = 16
SET JIT = OFF
AS
$$
DECLARE 
  __max_page_count INT := 10;

  __min_block_num INT;
  __count_pre_grouped_blocks INT;
  __count INT;
  __total_pages INT;

  _result hafbe_types.permlink[];
BEGIN
  WITH gather_operations AS MATERIALIZED (
    SELECT
	    ov.block_num,
      ov.id,
      ov.trx_in_block,
      ov.body_binary::jsonb->'value'->>'permlink' as permlink
    FROM hive.operations_view ov
    WHERE 
      ov.op_type_id = 1 AND
      ov.block_num <= _to AND
      ov.block_num >= _from AND
      ov.body_binary::jsonb->'value'->>'author' = _author AND (
        (_comment_type = 'post' AND ov.body_binary::jsonb->'value'->>'parent_author' = '') OR
        (_comment_type = 'comment' AND ov.body_binary::jsonb->'value'->>'parent_author' != '') OR
        (_comment_type = 'all')
      )
    ORDER BY ov.block_num DESC, ov.id DESC
    LIMIT (__max_page_count * _page_size) -- by default operation filter is limited to 10 pages
  ),
  group_by_permlink AS (
    SELECT 
      block_num,
      id,
      trx_in_block,
      permlink,
      ROW_NUMBER() OVER (PARTITION BY permlink ORDER BY id DESC) AS row_num
    FROM gather_operations
  ),
  eliminate_duplicate_permlink AS MATERIALIZED (
    SELECT 
      block_num,
      id,
      trx_in_block,
      permlink
    FROM group_by_permlink
    WHERE row_num = 1
  ),
  -----------PAGING LOGIC----------------
  -- Pages are counted differently compared to default.sql
  -- The results are based on a set of blocks for each operation, 
  -- so the count and total number of pages depend on the specific query inside this cte chain
  min_block_num AS (
    SELECT 
      MIN(block_num) AS block_num
    FROM eliminate_duplicate_permlink
  ),
  count_blocks AS MATERIALIZED (
    SELECT 
      COUNT(*) AS count
    FROM eliminate_duplicate_permlink
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
      'asc',
      _page_size
    )
  ),
  filter_page AS MATERIALIZED (
    SELECT 
      block_num,
      id,
      trx_in_block,
      permlink
    FROM eliminate_duplicate_permlink
    ORDER BY id DESC
    offset (SELECT offset_filter FROM calculate_pages)
    LIMIT (SELECT limit_filter FROM calculate_pages)
  ),
  ---------------------------------------
  result_query AS (
    SELECT 
      bo.block_num,
      bo.id,
      bo.permlink,
      bv.created_at,
      encode(tr.trx_hash, 'hex') AS trx_hash
    FROM filter_page bo
    JOIN hive.blocks_view bv ON bv.num = bo.block_num
    JOIN hive.transactions_view tr ON tr.block_num = bo.block_num AND tr.trx_in_block = bo.trx_in_block
  )
  SELECT 
    (SELECT count FROM count_blocks),
    (SELECT total_pages FROM calculate_pages),
    (SELECT block_num FROM min_block_num),
    (SELECT count FROM count_pre_grouped_blocks),
    (
      SELECT array_agg(rows ORDER BY id::BIGINT DESC) FROM (
        SELECT 
          s.permlink,
          s.block_num,
          s.trx_hash,
          s.created_at,
          s.id::TEXT
        FROM result_query s
      ) rows
    )
  INTO __count, __total_pages, __min_block_num, __count_pre_grouped_blocks, _result;

  -- 1. If the min block number is NULL - the result is empty - there are no results for whole provided range
  -- 2. If the min block number is NOT NULL and pages are not fully saturated it means there is no more blocks to fetch 
  -- 3. (ELSE) If the min block number is NOT NULL - the result is not empty - there are results for the provided range
  -- and the min block number can be used as filter in the next API call (as a to-block parameter)
  _from := (
    CASE
      WHEN __min_block_num IS NULL THEN _from
      WHEN __min_block_num IS NOT NULL AND __min_block_num = 1 THEN 1
      WHEN __min_block_num IS NOT NULL AND __min_block_num != 1 AND __count_pre_grouped_blocks != __max_page_count * _page_size THEN _from
      ELSE __min_block_num - 1
    END
  );

  RETURN (
    COALESCE(__count, 0),
    COALESCE(__total_pages, 0),
    (_from, _to)::hafbe_types.block_range,
    COALESCE(_result, '{}'::hafbe_types.permlink[])
  )::hafbe_types.permlink_history;

END
$$;

RESET ROLE;
