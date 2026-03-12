-- =============================================================================
-- Comment Permlinks Helper Functions
-- =============================================================================
-- Functions for retrieving permlinks (unique comment identifiers) for an author.
-- Used by the comment listing endpoint to paginate through an author's content.
-- =============================================================================

SET ROLE hafbe_owner;

/*
 * get_comment_permlinks: Retrieves unique permlinks for an author within a block range.
 *
 * Returns paginated list of permlinks with cursor-based navigation support.
 * Filters by comment type (posts, comments, or all) and deduplicates by permlink
 * since multiple operations can reference the same comment.
 *
 * PARAMETERS:
 *   _author       - Author account name
 *   _comment_type - Filter: 'post' (no parent), 'comment' (has parent), or 'all'
 *   _page         - Page number (1-based)
 *   _page_size    - Number of permlinks per page
 *   _from         - Starting block number
 *   _to           - Ending block number
 *
 * RETURNS: permlink_history with count, pages, block range, and permlink array
 *
 * CURSOR NAVIGATION:
 *   The returned block range can be used for cursor-based pagination.
 *   The from_block is adjusted based on the minimum block found in results,
 *   allowing the caller to continue fetching from where they left off.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.get_comment_permlinks(
    _author       TEXT,
    _comment_type hafbe_backend.comment_type,
    _page         INT,
    _page_size    INT,
    _from         INT,
    _to           INT
)
RETURNS hafbe_backend.permlink_history
LANGUAGE 'plpgsql' STABLE
SET join_collapse_limit = 16
SET from_collapse_limit = 16
SET JIT = OFF
AS
$$
DECLARE
  __op_comment               INT := hafbe_backend.op_comment();
  __max_page_count           INT := hafbe_backend.default_max_page_count();
  __min_block_num            INT;
  __count_pre_grouped_blocks INT;
  __count                    INT;
  __total_pages              INT;
  __result                   hafbe_backend.permlink[];
BEGIN
  WITH
  /*
   * ===========================================================================
   * CTE: gather_operations
   * ===========================================================================
   * WHY MATERIALIZED: Expensive JSON parsing, used by downstream CTEs.
   *
   * PURPOSE: Fetch all comment operations for the author within the block range.
   *
   * COMMENT TYPE FILTERING:
   *   - 'post':    parent_author is empty string (top-level posts)
   *   - 'comment': parent_author is non-empty (replies)
   *   - 'all':     no parent_author filter
   *
   * LIMIT: Restricts to max_page_count * page_size operations to bound query cost.
   */
  gather_operations AS MATERIALIZED (
    SELECT
      ov.block_num,
      ov.id,
      ov.trx_in_block,
      ov.body_value ->> 'permlink' AS permlink
    FROM hive.operations_view ov
    WHERE
      ov.op_type_id = __op_comment AND
      ov.block_num <= _to AND
      ov.block_num >= _from AND
      ov.body_value ->> 'author' = _author AND
      (
        (_comment_type = 'post'    AND ov.body_value ->> 'parent_author' = '') OR
        (_comment_type = 'comment' AND ov.body_value ->> 'parent_author' != '') OR
        (_comment_type = 'all')
      )
    ORDER BY ov.block_num DESC, ov.id DESC
    LIMIT (__max_page_count * _page_size)
  ),

  /*
   * ===========================================================================
   * CTE: group_by_permlink
   * ===========================================================================
   * PURPOSE: Assign row numbers within each permlink group.
   *
   * Multiple operations can affect the same permlink (edits, votes, etc).
   * We want only the most recent operation for each unique permlink.
   */
  group_by_permlink AS (
    SELECT
      block_num,
      id,
      trx_in_block,
      permlink,
      ROW_NUMBER() OVER (PARTITION BY permlink ORDER BY id DESC) AS row_num
    FROM gather_operations
  ),

  /*
   * ===========================================================================
   * CTE: eliminate_duplicate_permlink
   * ===========================================================================
   * WHY MATERIALIZED: Filtered result used by multiple downstream CTEs.
   *
   * PURPOSE: Keep only the most recent operation for each permlink (row_num = 1).
   */
  eliminate_duplicate_permlink AS MATERIALIZED (
    SELECT
      block_num,
      id,
      trx_in_block,
      permlink
    FROM group_by_permlink
    WHERE row_num = 1
  ),

  -- ===========================================================================
  -- PAGINATION LOGIC
  -- ===========================================================================
  -- Pages are counted based on unique permlinks, not raw operations.
  -- This differs from standard block-based pagination.

  /*
   * CTE: min_block_num
   * PURPOSE: Find the minimum block in results for cursor calculation.
   */
  min_block_num AS (
    SELECT MIN(block_num) AS block_num
    FROM eliminate_duplicate_permlink
  ),

  /*
   * CTE: count_blocks
   * PURPOSE: Count unique permlinks for pagination.
   */
  count_blocks AS MATERIALIZED (
    SELECT COUNT(*) AS count
    FROM eliminate_duplicate_permlink
  ),

  /*
   * CTE: count_pre_grouped_blocks
   * PURPOSE: Count total operations before deduplication.
   * Used to determine if we've exhausted the search window.
   */
  count_pre_grouped_blocks AS (
    SELECT COUNT(*) AS count
    FROM gather_operations
  ),

  /*
   * CTE: calculate_pages
   * PURPOSE: Calculate pagination parameters using shared utility.
   */
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

  /*
   * CTE: filter_page
   * PURPOSE: Apply pagination offset and limit.
   */
  filter_page AS MATERIALIZED (
    SELECT
      block_num,
      id,
      trx_in_block,
      permlink
    FROM eliminate_duplicate_permlink
    ORDER BY id DESC
    OFFSET (SELECT offset_filter FROM calculate_pages)
    LIMIT (SELECT limit_filter FROM calculate_pages)
  ),

  -- ===========================================================================
  -- RESULT ENRICHMENT
  -- ===========================================================================

  /*
   * CTE: result_query
   * PURPOSE: Join with blocks and transactions for timestamp and trx_hash.
   */
  result_query AS (
    SELECT
      bo.block_num,
      bo.id,
      bo.permlink,
      bv.created_at,
      encode(tr.trx_hash, 'hex') AS trx_hash
    FROM filter_page bo
    JOIN hive.blocks_view bv       ON bv.num = bo.block_num
    JOIN hive.transactions_view tr ON tr.block_num = bo.block_num AND tr.trx_in_block = bo.trx_in_block
  )

  /*
   * Collect results into variables for cursor calculation.
   */
  SELECT
    (SELECT count FROM count_blocks),
    (SELECT total_pages FROM calculate_pages),
    (SELECT block_num FROM min_block_num),
    (SELECT count FROM count_pre_grouped_blocks),
    (
      SELECT array_agg(rows ORDER BY id::BIGINT DESC)
      FROM (
        SELECT
          s.permlink,
          s.block_num,
          s.trx_hash,
          s.created_at,
          s.id::TEXT
        FROM result_query s
      ) rows
    )
  INTO __count, __total_pages, __min_block_num, __count_pre_grouped_blocks, __result;

  /*
   * CURSOR CALCULATION:
   * Calculate the next from_block for cursor-based pagination.
   *
   * Cases:
   *   1. No results (__min_block_num IS NULL):
   *      Keep original _from - no data in range
   *
   *   2. At genesis (__min_block_num = 1):
   *      Return 1 - can't go lower
   *
   *   3. Results not exhausted (pre_grouped_count < limit):
   *      Keep original _from - more data available in current range
   *
   *   4. Results exhausted:
   *      Return __min_block_num - 1 for next cursor
   */
  _from := (
    CASE
      WHEN __min_block_num IS NULL THEN
        _from
      WHEN __min_block_num = 1 THEN
        1
      WHEN __count_pre_grouped_blocks != __max_page_count * _page_size THEN
        _from
      ELSE
        __min_block_num - 1
    END
  );

  RETURN (
    COALESCE(__count, 0),
    COALESCE(__total_pages, 0),
    (_from, _to)::hafbe_backend.block_range,
    COALESCE(__result, '{}'::hafbe_backend.permlink[])
  )::hafbe_backend.permlink_history;
END
$$;

RESET ROLE;
