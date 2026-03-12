-- =============================================================================
-- Block Search Filters
-- =============================================================================
-- Consolidated from filtering_functions/*.sql
-- Contains all block search filter implementations
-- =============================================================================

SET ROLE hafbe_owner;

-- -----------------------------------------------------------------------------
-- Default filter (no operation filter)
-- From: default.sql
-- -----------------------------------------------------------------------------

/*
 * blocksearch_no_filter: Gathers blocks without any operation filter.
 *
 * Returns all blocks in the specified range using efficient SQL-level pagination.
 * This is the simplest gatherer - block count is calculated as (to - from + 1).
 *
 * PARAMETERS:
 *   _from     - Starting block (NULL = genesis)
 *   _to       - Ending block (NULL = current head)
 *   _order_is - Sort direction ('asc' or 'desc')
 *   _page     - Page number (1-based)
 *   _limit    - Page size
 *
 * RETURNS: gatherer_result with paginated blocks and operations
 */
CREATE OR REPLACE FUNCTION hafbe_backend.blocksearch_no_filter(
    _from     INT,
    _to       INT,
    _order_is hafbe_backend.sort_direction,
    _page     INT,
    _limit    INT
)
RETURNS hafbe_backend.gatherer_result
LANGUAGE 'plpgsql' STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET JIT = OFF
AS
$$
DECLARE
  __hafbe_current_block INT := (SELECT current_block_num FROM hafd.contexts WHERE name = 'hafbe_app');
  __count               INT;
  __from                INT;
  __to                  INT;
  __total_pages         INT;
  __offset              INT;
  __limit_size          INT;
  __blocks              hafbe_backend.gathered_block[];
BEGIN
  -- Get count and normalized range
  SELECT count_blocks, from_block, to_block
  INTO __count, __from, __to
  FROM hafbe_backend.blocksearch_no_filter_count(_from, _to, __hafbe_current_block);

  -- Calculate pagination
  SELECT total_pages, offset_filter, limit_filter
  INTO __total_pages, __offset, __limit_size
  FROM hafbe_backend.blocksearch_calculate_pages(__count, _page, _order_is, _limit);

  -- Empty result case
  IF __total_pages = 0 THEN
    RETURN (
      '{}'::hafbe_backend.gathered_block[],
      __count,
      __total_pages,
      NULL::INT,  -- min_block_num: NULL indicates no cursor adjustment needed
      __count,    -- pre_grouped_count
      __count,    -- max_page_limit: same as count so cursor logic returns range_from
      __from,
      __to
    )::hafbe_backend.gatherer_result;
  END IF;

  -- Gather blocks with operations (no enrichment yet)
  SELECT array_agg(row ORDER BY
    (CASE WHEN _order_is = 'desc' THEN row.block_num ELSE NULL END) DESC,
    (CASE WHEN _order_is = 'asc' THEN row.block_num ELSE NULL END) ASC
  )
  INTO __blocks
  FROM (
    SELECT
      bv.num AS block_num,
      hafbe_backend.get_block_operation_aggregation(bv.num) AS operations
    FROM hive.blocks_view bv
    WHERE
      bv.num >= __from AND
      bv.num <= __to AND
      (_order_is = 'desc' OR bv.num >= __from + __offset) AND
      (_order_is = 'asc' OR bv.num <= __to - __offset)
    ORDER BY
      (CASE WHEN _order_is = 'desc' THEN bv.num ELSE NULL END) DESC,
      (CASE WHEN _order_is = 'asc' THEN bv.num ELSE NULL END) ASC
    LIMIT __limit_size
  ) row;

  RETURN (
    COALESCE(__blocks, '{}'::hafbe_backend.gathered_block[]),
    COALESCE(__count, 0),
    COALESCE(__total_pages, 0),
    NULL::INT,  -- min_block_num: NULL so cursor = range_from (no adjustment)
    __count,    -- pre_grouped_count
    __count,    -- max_page_limit
    __from,
    __to
  )::hafbe_backend.gatherer_result;
END
$$;

-- -----------------------------------------------------------------------------
-- Single operation filter
-- From: by_operation.sql
-- -----------------------------------------------------------------------------

/*
 * blocksearch_single_op: Gathers blocks containing a specific operation type.
 *
 * Uses the block_operations table for efficient filtering.
 *
 * PARAMETERS:
 *   _operation - Operation type ID to filter by
 *   _from      - Starting block (NULL = genesis)
 *   _to        - Ending block (NULL = current head)
 *   _order_is  - Sort direction ('asc' or 'desc')
 *   _page      - Page number (1-based)
 *   _limit     - Page size
 *
 * RETURNS: gatherer_result with paginated blocks matching the operation
 */
CREATE OR REPLACE FUNCTION hafbe_backend.blocksearch_single_op(
    _operation INT,
    _from      INT,
    _to        INT,
    _order_is  hafbe_backend.sort_direction,
    _page      INT,
    _limit     INT
)
RETURNS hafbe_backend.gatherer_result
LANGUAGE 'plpgsql' STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET JIT = OFF
AS
$$
DECLARE
  __hafbe_current_block INT := (SELECT current_block_num FROM hafd.contexts WHERE name = 'hafbe_app');
  __max_page_count      INT := 10;
  __min_block_num       INT;
  __count               INT;
  __from                INT;
  __to                  INT;
  __total_pages         INT;
  __blocks              hafbe_backend.gathered_block[];
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
  min_block_num AS (
    SELECT MIN(block_num) AS block_num
    FROM eliminate_duplicate_blocks
  ),
  count_blocks AS MATERIALIZED (
    SELECT COUNT(*) AS count
    FROM eliminate_duplicate_blocks
  ),
  calculate_pages AS MATERIALIZED (
    SELECT total_pages, offset_filter, limit_filter
    FROM hafbe_backend.blocksearch_calculate_pages(
      (SELECT count FROM count_blocks)::INT,
      _page,
      _order_is,
      _limit
    )
  ),
  filter_page AS MATERIALIZED (
    SELECT block_num, operations
    FROM eliminate_duplicate_blocks
    ORDER BY
      (CASE WHEN _order_is = 'desc' THEN block_num ELSE NULL END) DESC,
      (CASE WHEN _order_is = 'asc' THEN block_num ELSE NULL END) ASC
    OFFSET (SELECT offset_filter FROM calculate_pages)
    LIMIT (SELECT limit_filter FROM calculate_pages)
  )
  SELECT
    (SELECT count FROM count_blocks),
    (SELECT total_pages FROM calculate_pages),
    (SELECT block_num FROM min_block_num),
    (
      SELECT array_agg((block_num, operations)::hafbe_backend.gathered_block ORDER BY
        (CASE WHEN _order_is = 'desc' THEN block_num ELSE NULL END) DESC,
        (CASE WHEN _order_is = 'asc' THEN block_num ELSE NULL END) ASC
      )
      FROM filter_page
    )
  INTO __count, __total_pages, __min_block_num, __blocks;

  RETURN (
    COALESCE(__blocks, '{}'::hafbe_backend.gathered_block[]),
    COALESCE(__count, 0),
    COALESCE(__total_pages, 0),
    __min_block_num,
    __count,                       -- pre_grouped_count (same as count for single_op)
    __max_page_count * _limit,     -- max_page_limit
    __from,
    __to
  )::hafbe_backend.gatherer_result;
END
$$;

-- -----------------------------------------------------------------------------
-- Operation with key-value filter
-- From: by_operation_key_value.sql
-- -----------------------------------------------------------------------------

/*
 * blocksearch_key_value: Gathers blocks with operations matching key-value filters.
 *
 * Filters operations by operation type and JSON key-value pairs.
 *
 * PARAMETERS:
 *   _operation   - Operation type ID to filter by
 *   _from        - Starting block (NULL = genesis)
 *   _to          - Ending block (NULL = current head)
 *   _order_is    - Sort direction ('asc' or 'desc')
 *   _page        - Page number (1-based)
 *   _limit       - Page size
 *   _key_content - Array of values to match [val1, val2, val3]
 *   _setof_keys  - JSON array of paths [[path1], [path2], [path3]]
 *
 * RETURNS: gatherer_result with paginated blocks matching the filter
 */
CREATE OR REPLACE FUNCTION hafbe_backend.blocksearch_key_value(
    _operation   INT,
    _from        INT,
    _to          INT,
    _order_is    hafbe_backend.sort_direction,
    _page        INT,
    _limit       INT,
    _key_content TEXT[],
    _setof_keys  JSON
)
RETURNS hafbe_backend.gatherer_result
LANGUAGE 'plpgsql' STABLE
SET plan_cache_mode = force_custom_plan
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET JIT = OFF
AS
$$
DECLARE
  __hafbe_current_block      INT    := (SELECT current_block_num FROM hafd.contexts WHERE name = 'hafbe_app');
  __max_page_count           INT    := 10;
  __min_block_num            INT;
  __count_pre_grouped_blocks INT;
  __count                    INT;
  __from                     INT;
  __to                       INT;
  __total_pages              INT;
  __blocks                   hafbe_backend.gathered_block[];
  -- Keys must be declared separately for planner to use indexes
  _path1                     TEXT[] := ARRAY(SELECT json_array_elements_text(_setof_keys->0));
  _path2                     TEXT[] := ARRAY(SELECT json_array_elements_text(_setof_keys->1));
  _path3                     TEXT[] := ARRAY(SELECT json_array_elements_text(_setof_keys->2));
  -- Strip leading 'value' element so paths match body_value indexes
  _path1_inner               TEXT[] := CASE WHEN _path1[1] = 'value' THEN _path1[2:] ELSE _path1 END;
  _path2_inner               TEXT[] := CASE WHEN _path2[1] = 'value' THEN _path2[2:] ELSE _path2 END;
  _path3_inner               TEXT[] := CASE WHEN _path3[1] = 'value' THEN _path3[2:] ELSE _path3 END;
BEGIN
  SELECT from_block, to_block
  INTO __from, __to
  FROM hafbe_backend.blocksearch_range(_from, _to, __hafbe_current_block);

  WITH gather_operations AS MATERIALIZED (
    SELECT
      ov.block_num,
      ov.op_type_id
    FROM hive.operations_view ov
    WHERE
      ov.op_type_id = _operation AND
      ov.block_num <= __to AND
      ov.block_num >= __from AND
      ((_key_content[1] IS NULL) OR jsonb_extract_path_text(ov.body_value, VARIADIC _path1_inner) = _key_content[1]) AND
      ((_key_content[2] IS NULL) OR jsonb_extract_path_text(ov.body_value, VARIADIC _path2_inner) = _key_content[2]) AND
      ((_key_content[3] IS NULL) OR jsonb_extract_path_text(ov.body_value, VARIADIC _path3_inner) = _key_content[3])
    ORDER BY
      (CASE WHEN _order_is = 'desc' THEN ov.block_num ELSE NULL END) DESC,
      (CASE WHEN _order_is = 'asc' THEN ov.block_num ELSE NULL END) ASC
    LIMIT (__max_page_count * _limit)
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
  min_block_num AS (
    SELECT MIN(block_num) AS block_num
    FROM eliminate_duplicate_blocks
  ),
  count_blocks AS MATERIALIZED (
    SELECT COUNT(*) AS count
    FROM eliminate_duplicate_blocks
  ),
  count_pre_grouped_blocks AS (
    SELECT COUNT(*) AS count
    FROM gather_operations
  ),
  calculate_pages AS MATERIALIZED (
    SELECT total_pages, offset_filter, limit_filter
    FROM hafbe_backend.blocksearch_calculate_pages(
      (SELECT count FROM count_blocks)::INT,
      _page,
      _order_is,
      _limit
    )
  ),
  filter_page AS MATERIALIZED (
    SELECT block_num, operations
    FROM eliminate_duplicate_blocks
    ORDER BY
      (CASE WHEN _order_is = 'desc' THEN block_num ELSE NULL END) DESC,
      (CASE WHEN _order_is = 'asc' THEN block_num ELSE NULL END) ASC
    OFFSET (SELECT offset_filter FROM calculate_pages)
    LIMIT (SELECT limit_filter FROM calculate_pages)
  )
  SELECT
    (SELECT count FROM count_blocks),
    (SELECT total_pages FROM calculate_pages),
    (SELECT block_num FROM min_block_num),
    (SELECT count FROM count_pre_grouped_blocks),
    (
      SELECT array_agg((block_num, operations)::hafbe_backend.gathered_block ORDER BY
        (CASE WHEN _order_is = 'desc' THEN block_num ELSE NULL END) DESC,
        (CASE WHEN _order_is = 'asc' THEN block_num ELSE NULL END) ASC
      )
      FROM filter_page
    )
  INTO __count, __total_pages, __min_block_num, __count_pre_grouped_blocks, __blocks;

  RETURN (
    COALESCE(__blocks, '{}'::hafbe_backend.gathered_block[]),
    COALESCE(__count, 0),
    COALESCE(__total_pages, 0),
    __min_block_num,
    __count_pre_grouped_blocks,
    __max_page_count * _limit,
    __from,
    __to
  )::hafbe_backend.gatherer_result;
END
$$;

-- -----------------------------------------------------------------------------
-- Multiple operations filter
-- From: by_multiple_operations.sql
-- -----------------------------------------------------------------------------

/*
 * blocksearch_multi_op: Gathers blocks containing any of multiple operation types.
 *
 * Uses CROSS JOIN with find_blocks_with_op to efficiently search for multiple ops.
 *
 * PARAMETERS:
 *   _operations - Array of operation type IDs to filter by
 *   _from       - Starting block (NULL = genesis)
 *   _to         - Ending block (NULL = current head)
 *   _order_is   - Sort direction ('asc' or 'desc')
 *   _page       - Page number (1-based)
 *   _limit      - Page size
 *
 * RETURNS: gatherer_result with paginated blocks matching any operation
 */
CREATE OR REPLACE FUNCTION hafbe_backend.blocksearch_multi_op(
    _operations INT[],
    _from       INT,
    _to         INT,
    _order_is   hafbe_backend.sort_direction,
    _page       INT,
    _limit      INT
)
RETURNS hafbe_backend.gatherer_result
LANGUAGE 'plpgsql' STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET JIT = OFF
AS
$$
DECLARE
  __hafbe_current_block      INT := (SELECT current_block_num FROM hafd.contexts WHERE name = 'hafbe_app');
  __max_page_count           INT := array_length(_operations, 1);
  __min_block_num            INT;
  __count_pre_grouped_blocks INT;
  __count                    INT;
  __from                     INT;
  __to                       INT;
  __total_pages              INT;
  __blocks                   hafbe_backend.gathered_block[];
BEGIN
  SELECT from_block, to_block
  INTO __from, __to
  FROM hafbe_backend.blocksearch_range(_from, _to, __hafbe_current_block);

  WITH gather_operations AS (
    SELECT
      moh.block_num,
      moh.op_type_id,
      moh.op_count
    FROM
      unnest(_operations) AS op_type_id
    CROSS JOIN
      hafbe_backend.find_blocks_with_op(op_type_id, __from, __to, _order_is, _limit) moh
  ),
  eliminate_duplicate_blocks AS MATERIALIZED (
    SELECT
      gb.block_num,
      array_agg((op_type_id, op_count)::hafbe_backend.block_operations) AS operations
    FROM gather_operations gb
    GROUP BY gb.block_num
  ),
  min_block_num AS (
    SELECT MIN(block_num) AS block_num
    FROM eliminate_duplicate_blocks
  ),
  count_blocks AS MATERIALIZED (
    SELECT COUNT(*) AS count
    FROM eliminate_duplicate_blocks
  ),
  count_pre_grouped_blocks AS (
    SELECT COUNT(*) AS count
    FROM gather_operations
  ),
  calculate_pages AS MATERIALIZED (
    SELECT total_pages, offset_filter, limit_filter
    FROM hafbe_backend.blocksearch_calculate_pages(
      (SELECT count FROM count_blocks)::INT,
      _page,
      _order_is,
      _limit
    )
  ),
  filter_page AS MATERIALIZED (
    SELECT block_num, operations
    FROM eliminate_duplicate_blocks
    ORDER BY
      (CASE WHEN _order_is = 'desc' THEN block_num ELSE NULL END) DESC,
      (CASE WHEN _order_is = 'asc' THEN block_num ELSE NULL END) ASC
    OFFSET (SELECT offset_filter FROM calculate_pages)
    LIMIT (SELECT limit_filter FROM calculate_pages)
  )
  SELECT
    (SELECT count FROM count_blocks),
    (SELECT total_pages FROM calculate_pages),
    (SELECT block_num FROM min_block_num),
    (SELECT count FROM count_pre_grouped_blocks),
    (
      SELECT array_agg((block_num, operations)::hafbe_backend.gathered_block ORDER BY
        (CASE WHEN _order_is = 'desc' THEN block_num ELSE NULL END) DESC,
        (CASE WHEN _order_is = 'asc' THEN block_num ELSE NULL END) ASC
      )
      FROM filter_page
    )
  INTO __count, __total_pages, __min_block_num, __count_pre_grouped_blocks, __blocks;

  RETURN (
    COALESCE(__blocks, '{}'::hafbe_backend.gathered_block[]),
    COALESCE(__count, 0),
    COALESCE(__total_pages, 0),
    __min_block_num,
    __count_pre_grouped_blocks,
    __max_page_count * _limit,
    __from,
    __to
  )::hafbe_backend.gatherer_result;
END
$$;

-- -----------------------------------------------------------------------------
-- Account filter (all operations for account)
-- From: by_account.sql
-- -----------------------------------------------------------------------------

/*
 * blocksearch_account: Gathers blocks containing operations for a specific account.
 *
 * Uses account_operations_view with sequence number range for efficient filtering.
 *
 * PARAMETERS:
 *   _account_id - Account ID to filter by
 *   _from       - Starting block (NULL = genesis)
 *   _to         - Ending block (NULL = current head)
 *   _order_is   - Sort direction ('asc' or 'desc')
 *   _page       - Page number (1-based)
 *   _limit      - Page size
 *
 * RETURNS: gatherer_result with paginated blocks for the account
 */
CREATE OR REPLACE FUNCTION hafbe_backend.blocksearch_account(
    _account_id INT,
    _from       INT,
    _to         INT,
    _order_is   hafbe_backend.sort_direction,
    _page       INT,
    _limit      INT
)
RETURNS hafbe_backend.gatherer_result
LANGUAGE 'plpgsql' STABLE
SET join_collapse_limit = 16
SET from_collapse_limit = 16
SET JIT = OFF
AS
$$
DECLARE
  __hafbe_current_block      INT := (SELECT current_block_num FROM hafd.contexts WHERE name = 'hafbe_app');
  __max_page_count           INT := 10;
  __from_seq                 INT;
  __to_seq                   INT;
  __min_block_num            INT;
  __count_pre_grouped_blocks INT;
  __count                    INT;
  __from                     INT;
  __to                       INT;
  __total_pages              INT;
  __blocks                   hafbe_backend.gathered_block[];
BEGIN
  SELECT from_block, to_block, from_seq, to_seq
  INTO __from, __to, __from_seq, __to_seq
  FROM hafbe_backend.blocksearch_account_range(_account_id, _from, _to, __hafbe_current_block);

  WITH gather_operations AS MATERIALIZED (
    SELECT
      aov.block_num,
      aov.op_type_id
    FROM hive.account_operations_view aov
    WHERE
      aov.account_id = _account_id AND
      aov.account_op_seq_no <= __to_seq AND
      aov.account_op_seq_no >= __from_seq
    ORDER BY
      (CASE WHEN _order_is = 'desc' THEN aov.account_op_seq_no ELSE NULL END) DESC,
      (CASE WHEN _order_is = 'asc' THEN aov.account_op_seq_no ELSE NULL END) ASC
    LIMIT (__max_page_count * _limit)
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
      array_agg((op_type_id, op_count)::hafbe_backend.block_operations) AS operations
    FROM group_by_type_and_block
    GROUP BY block_num
  ),
  min_block_num AS (
    SELECT MIN(block_num) AS block_num
    FROM eliminate_duplicate_blocks
  ),
  count_blocks AS MATERIALIZED (
    SELECT COUNT(*) AS count
    FROM eliminate_duplicate_blocks
  ),
  count_pre_grouped_blocks AS (
    SELECT COUNT(*) AS count
    FROM gather_operations
  ),
  calculate_pages AS MATERIALIZED (
    SELECT total_pages, offset_filter, limit_filter
    FROM hafbe_backend.blocksearch_calculate_pages(
      (SELECT count FROM count_blocks)::INT,
      _page,
      _order_is,
      _limit
    )
  ),
  filter_page AS MATERIALIZED (
    SELECT block_num, operations
    FROM eliminate_duplicate_blocks
    ORDER BY
      (CASE WHEN _order_is = 'desc' THEN block_num ELSE NULL END) DESC,
      (CASE WHEN _order_is = 'asc' THEN block_num ELSE NULL END) ASC
    OFFSET (SELECT offset_filter FROM calculate_pages)
    LIMIT (SELECT limit_filter FROM calculate_pages)
  )
  SELECT
    (SELECT count FROM count_blocks),
    (SELECT total_pages FROM calculate_pages),
    (SELECT block_num FROM min_block_num),
    (SELECT count FROM count_pre_grouped_blocks),
    (
      SELECT array_agg((block_num, operations)::hafbe_backend.gathered_block ORDER BY
        (CASE WHEN _order_is = 'desc' THEN block_num ELSE NULL END) DESC,
        (CASE WHEN _order_is = 'asc' THEN block_num ELSE NULL END) ASC
      )
      FROM filter_page
    )
  INTO __count, __total_pages, __min_block_num, __count_pre_grouped_blocks, __blocks;

  RETURN (
    COALESCE(__blocks, '{}'::hafbe_backend.gathered_block[]),
    COALESCE(__count, 0),
    COALESCE(__total_pages, 0),
    __min_block_num,
    __count_pre_grouped_blocks,
    __max_page_count * _limit,
    __from,
    __to
  )::hafbe_backend.gatherer_result;
END
$$;

-- -----------------------------------------------------------------------------
-- Account + operation filter
-- From: by_account_operation.sql
-- -----------------------------------------------------------------------------

/*
 * blocksearch_account_op: Gathers blocks with specific operation for a specific account.
 *
 * Filters by both account ID and operation type.
 *
 * PARAMETERS:
 *   _operation  - Operation type ID to filter by
 *   _account_id - Account ID to filter by
 *   _from       - Starting block (NULL = genesis)
 *   _to         - Ending block (NULL = current head)
 *   _order_is   - Sort direction ('asc' or 'desc')
 *   _page       - Page number (1-based)
 *   _limit      - Page size
 *
 * RETURNS: gatherer_result with paginated blocks matching both filters
 */
CREATE OR REPLACE FUNCTION hafbe_backend.blocksearch_account_op(
    _operation  INT,
    _account_id INT,
    _from       INT,
    _to         INT,
    _order_is   hafbe_backend.sort_direction,
    _page       INT,
    _limit      INT
)
RETURNS hafbe_backend.gatherer_result
LANGUAGE 'plpgsql' STABLE
SET join_collapse_limit = 16
SET from_collapse_limit = 16
SET JIT = OFF
AS
$$
DECLARE
  __hafbe_current_block      INT := (SELECT current_block_num FROM hafd.contexts WHERE name = 'hafbe_app');
  __max_page_count           INT := 10;
  __min_block_num            INT;
  __count_pre_grouped_blocks INT;
  __count                    INT;
  __from                     INT;
  __to                       INT;
  __total_pages              INT;
  __blocks                   hafbe_backend.gathered_block[];
BEGIN
  SELECT from_block, to_block
  INTO __from, __to
  FROM hafbe_backend.blocksearch_range(_from, _to, __hafbe_current_block);

  WITH gather_operations AS MATERIALIZED (
    SELECT
      aov.block_num,
      aov.op_type_id
    FROM hive.account_operations_view aov
    WHERE
      aov.op_type_id = _operation AND
      aov.account_id = _account_id AND
      aov.block_num >= __from AND
      aov.block_num <= __to
    ORDER BY
      (CASE WHEN _order_is = 'desc' THEN aov.block_num ELSE NULL END) DESC,
      (CASE WHEN _order_is = 'asc' THEN aov.block_num ELSE NULL END) ASC
    LIMIT (__max_page_count * _limit)
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
  min_block_num AS (
    SELECT MIN(block_num) AS block_num
    FROM eliminate_duplicate_blocks
  ),
  count_blocks AS MATERIALIZED (
    SELECT COUNT(*) AS count
    FROM eliminate_duplicate_blocks
  ),
  count_pre_grouped_blocks AS (
    SELECT COUNT(*) AS count
    FROM gather_operations
  ),
  calculate_pages AS MATERIALIZED (
    SELECT total_pages, offset_filter, limit_filter
    FROM hafbe_backend.blocksearch_calculate_pages(
      (SELECT count FROM count_blocks)::INT,
      _page,
      _order_is,
      _limit
    )
  ),
  filter_page AS MATERIALIZED (
    SELECT block_num, operations
    FROM eliminate_duplicate_blocks
    ORDER BY
      (CASE WHEN _order_is = 'desc' THEN block_num ELSE NULL END) DESC,
      (CASE WHEN _order_is = 'asc' THEN block_num ELSE NULL END) ASC
    OFFSET (SELECT offset_filter FROM calculate_pages)
    LIMIT (SELECT limit_filter FROM calculate_pages)
  )
  SELECT
    (SELECT count FROM count_blocks),
    (SELECT total_pages FROM calculate_pages),
    (SELECT block_num FROM min_block_num),
    (SELECT count FROM count_pre_grouped_blocks),
    (
      SELECT array_agg((block_num, operations)::hafbe_backend.gathered_block ORDER BY
        (CASE WHEN _order_is = 'desc' THEN block_num ELSE NULL END) DESC,
        (CASE WHEN _order_is = 'asc' THEN block_num ELSE NULL END) ASC
      )
      FROM filter_page
    )
  INTO __count, __total_pages, __min_block_num, __count_pre_grouped_blocks, __blocks;

  RETURN (
    COALESCE(__blocks, '{}'::hafbe_backend.gathered_block[]),
    COALESCE(__count, 0),
    COALESCE(__total_pages, 0),
    __min_block_num,
    __count_pre_grouped_blocks,
    __max_page_count * _limit,
    __from,
    __to
  )::hafbe_backend.gatherer_result;
END
$$;

-- -----------------------------------------------------------------------------
-- Account + operation + key-value filter
-- From: by_account_operation_key_value.sql
-- -----------------------------------------------------------------------------

/*
 * blocksearch_account_key_value: Gathers blocks with account + op + key-value filters.
 *
 * Filters by account ID, operation type, and JSON key-value pairs.
 *
 * PARAMETERS:
 *   _operation   - Operation type ID to filter by
 *   _account_id  - Account ID to filter by
 *   _from        - Starting block (NULL = genesis)
 *   _to          - Ending block (NULL = current head)
 *   _order_is    - Sort direction ('asc' or 'desc')
 *   _page        - Page number (1-based)
 *   _limit       - Page size
 *   _key_content - Array of values to match [val1, val2, val3]
 *   _setof_keys  - JSON array of paths [[path1], [path2], [path3]]
 *
 * RETURNS: gatherer_result with paginated blocks matching all filters
 */
CREATE OR REPLACE FUNCTION hafbe_backend.blocksearch_account_key_value(
    _operation   INT,
    _account_id  INT,
    _from        INT,
    _to          INT,
    _order_is    hafbe_backend.sort_direction,
    _page        INT,
    _limit       INT,
    _key_content TEXT[],
    _setof_keys  JSON
)
RETURNS hafbe_backend.gatherer_result
LANGUAGE 'plpgsql' STABLE
SET plan_cache_mode = force_custom_plan
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET JIT = OFF
AS
$$
DECLARE
  __hafbe_current_block      INT    := (SELECT current_block_num FROM hafd.contexts WHERE name = 'hafbe_app');
  __max_page_count           INT    := 10;
  __min_block_num            INT;
  __count_pre_grouped_blocks INT;
  __count                    INT;
  __from                     INT;
  __to                       INT;
  __total_pages              INT;
  __blocks                   hafbe_backend.gathered_block[];
  -- Keys must be declared separately for planner to use indexes
  _path1                     TEXT[] := ARRAY(SELECT json_array_elements_text(_setof_keys->0));
  _path2                     TEXT[] := ARRAY(SELECT json_array_elements_text(_setof_keys->1));
  _path3                     TEXT[] := ARRAY(SELECT json_array_elements_text(_setof_keys->2));
  -- Strip leading 'value' element so paths match body_value indexes
  _path1_inner               TEXT[] := CASE WHEN _path1[1] = 'value' THEN _path1[2:] ELSE _path1 END;
  _path2_inner               TEXT[] := CASE WHEN _path2[1] = 'value' THEN _path2[2:] ELSE _path2 END;
  _path3_inner               TEXT[] := CASE WHEN _path3[1] = 'value' THEN _path3[2:] ELSE _path3 END;
BEGIN
  SELECT from_block, to_block
  INTO __from, __to
  FROM hafbe_backend.blocksearch_range(_from, _to, __hafbe_current_block);

  WITH source_ops AS (
    SELECT
      aov.block_num,
      aov.operation_id,
      aov.op_type_id
    FROM hive.account_operations_view aov
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
      ((_key_content[1] IS NULL) OR jsonb_extract_path_text(ov.body_value, VARIADIC _path1_inner) = _key_content[1]) AND
      ((_key_content[2] IS NULL) OR jsonb_extract_path_text(ov.body_value, VARIADIC _path2_inner) = _key_content[2]) AND
      ((_key_content[3] IS NULL) OR jsonb_extract_path_text(ov.body_value, VARIADIC _path3_inner) = _key_content[3])
    ORDER BY
      (CASE WHEN _order_is = 'desc' THEN ov.block_num ELSE NULL END) DESC,
      (CASE WHEN _order_is = 'asc' THEN ov.block_num ELSE NULL END) ASC
  ),
  gather_operations AS MATERIALIZED (
    SELECT
      so.block_num,
      so.op_type_id
    FROM source_ops so
    JOIN filter_by_key fbk ON so.operation_id = fbk.id
    LIMIT (__max_page_count * _limit)
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
  min_block_num AS (
    SELECT MIN(block_num) AS block_num
    FROM eliminate_duplicate_blocks
  ),
  count_blocks AS MATERIALIZED (
    SELECT COUNT(*) AS count
    FROM eliminate_duplicate_blocks
  ),
  count_pre_grouped_blocks AS (
    SELECT COUNT(*) AS count
    FROM gather_operations
  ),
  calculate_pages AS MATERIALIZED (
    SELECT total_pages, offset_filter, limit_filter
    FROM hafbe_backend.blocksearch_calculate_pages(
      (SELECT count FROM count_blocks)::INT,
      _page,
      _order_is,
      _limit
    )
  ),
  filter_page AS MATERIALIZED (
    SELECT block_num, operations
    FROM eliminate_duplicate_blocks
    ORDER BY
      (CASE WHEN _order_is = 'desc' THEN block_num ELSE NULL END) DESC,
      (CASE WHEN _order_is = 'asc' THEN block_num ELSE NULL END) ASC
    OFFSET (SELECT offset_filter FROM calculate_pages)
    LIMIT (SELECT limit_filter FROM calculate_pages)
  )
  SELECT
    (SELECT count FROM count_blocks),
    (SELECT total_pages FROM calculate_pages),
    (SELECT block_num FROM min_block_num),
    (SELECT count FROM count_pre_grouped_blocks),
    (
      SELECT array_agg((block_num, operations)::hafbe_backend.gathered_block ORDER BY
        (CASE WHEN _order_is = 'desc' THEN block_num ELSE NULL END) DESC,
        (CASE WHEN _order_is = 'asc' THEN block_num ELSE NULL END) ASC
      )
      FROM filter_page
    )
  INTO __count, __total_pages, __min_block_num, __count_pre_grouped_blocks, __blocks;

  RETURN (
    COALESCE(__blocks, '{}'::hafbe_backend.gathered_block[]),
    COALESCE(__count, 0),
    COALESCE(__total_pages, 0),
    __min_block_num,
    __count_pre_grouped_blocks,
    __max_page_count * _limit,
    __from,
    __to
  )::hafbe_backend.gatherer_result;
END
$$;

-- -----------------------------------------------------------------------------
-- Account + multiple operations filter
-- From: by_account_multi_operations.sql
-- -----------------------------------------------------------------------------

/*
 * blocksearch_account_multi_op: Gathers blocks with multiple operations for an account.
 *
 * Uses CROSS JOIN with find_blocks_with_op_and_account for efficient multi-op search.
 *
 * PARAMETERS:
 *   _operations - Array of operation type IDs to filter by
 *   _account_id - Account ID to filter by
 *   _from       - Starting block (NULL = genesis)
 *   _to         - Ending block (NULL = current head)
 *   _order_is   - Sort direction ('asc' or 'desc')
 *   _page       - Page number (1-based)
 *   _limit      - Page size
 *
 * RETURNS: gatherer_result with paginated blocks matching account and any operation
 */
CREATE OR REPLACE FUNCTION hafbe_backend.blocksearch_account_multi_op(
    _operations INT[],
    _account_id INT,
    _from       INT,
    _to         INT,
    _order_is   hafbe_backend.sort_direction,
    _page       INT,
    _limit      INT
)
RETURNS hafbe_backend.gatherer_result
LANGUAGE 'plpgsql' STABLE
SET join_collapse_limit = 16
SET from_collapse_limit = 16
SET JIT = OFF
AS
$$
DECLARE
  __hafbe_current_block      INT := (SELECT current_block_num FROM hafd.contexts WHERE name = 'hafbe_app');
  __max_page_count           INT := array_length(_operations, 1);
  __min_block_num            INT;
  __count_pre_grouped_blocks INT;
  __count                    INT;
  __from                     INT;
  __to                       INT;
  __total_pages              INT;
  __blocks                   hafbe_backend.gathered_block[];
BEGIN
  SELECT from_block, to_block
  INTO __from, __to
  FROM hafbe_backend.blocksearch_range(_from, _to, __hafbe_current_block);

  WITH gather_operations AS MATERIALIZED (
    SELECT
      moh.block_num,
      moh.op_type_id
    FROM
      unnest(_operations) AS op_type_id
    CROSS JOIN
      hafbe_backend.find_blocks_with_op_and_account(op_type_id, _account_id, __from, __to, _order_is, _limit) moh
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
      array_agg((op_type_id, op_count)::hafbe_backend.block_operations) AS operations
    FROM group_by_type_and_block
    GROUP BY block_num
  ),
  min_block_num AS (
    SELECT MIN(block_num) AS block_num
    FROM eliminate_duplicate_blocks
  ),
  count_blocks AS MATERIALIZED (
    SELECT COUNT(*) AS count
    FROM eliminate_duplicate_blocks
  ),
  count_pre_grouped_blocks AS (
    SELECT COUNT(*) AS count
    FROM gather_operations
  ),
  calculate_pages AS MATERIALIZED (
    SELECT total_pages, offset_filter, limit_filter
    FROM hafbe_backend.blocksearch_calculate_pages(
      (SELECT count FROM count_blocks)::INT,
      _page,
      _order_is,
      _limit
    )
  ),
  filter_page AS MATERIALIZED (
    SELECT block_num, operations
    FROM eliminate_duplicate_blocks
    ORDER BY
      (CASE WHEN _order_is = 'desc' THEN block_num ELSE NULL END) DESC,
      (CASE WHEN _order_is = 'asc' THEN block_num ELSE NULL END) ASC
    OFFSET (SELECT offset_filter FROM calculate_pages)
    LIMIT (SELECT limit_filter FROM calculate_pages)
  )
  SELECT
    (SELECT count FROM count_blocks),
    (SELECT total_pages FROM calculate_pages),
    (SELECT block_num FROM min_block_num),
    (SELECT count FROM count_pre_grouped_blocks),
    (
      SELECT array_agg((block_num, operations)::hafbe_backend.gathered_block ORDER BY
        (CASE WHEN _order_is = 'desc' THEN block_num ELSE NULL END) DESC,
        (CASE WHEN _order_is = 'asc' THEN block_num ELSE NULL END) ASC
      )
      FROM filter_page
    )
  INTO __count, __total_pages, __min_block_num, __count_pre_grouped_blocks, __blocks;

  RETURN (
    COALESCE(__blocks, '{}'::hafbe_backend.gathered_block[]),
    COALESCE(__count, 0),
    COALESCE(__total_pages, 0),
    __min_block_num,
    __count_pre_grouped_blocks,
    __max_page_count * _limit,
    __from,
    __to
  )::hafbe_backend.gatherer_result;
END
$$;

RESET ROLE;
