SET ROLE hafbe_owner;

-- ============================================================================
-- Block Search Utilities
-- ============================================================================
-- Functions and types for searching and filtering blocks by various criteria.
-- These support the block search API endpoints with filtering, pagination,
-- and operation-based queries.
--
-- MAIN COMPONENTS:
--   1. Block Data Functions - Retrieve block-specific data
--   2. Filter Return Types - moved to backend/types/blocksearch.sql
--   3. Range Calculation Functions - Calculate valid block ranges
--   4. Pagination Functions - Handle page calculations
--   5. Block Search Functions - Find blocks matching criteria
--
-- DESIGN PATTERN:
--   Most functions return composite types to bundle related data together.
--   This reduces the number of database round-trips for API calls.
-- ============================================================================

-- ============================================================================
-- SECTION 1: Block Data Functions
-- ============================================================================
-- Functions for retrieving specific data about individual blocks.
-- ============================================================================

/*
 * get_producer_reward: Retrieves the producer reward for a specific block.
 *
 * PARAMETERS:
 *   _block_num - The block number to query
 *
 * RETURNS: The vesting shares reward amount in VESTS (as BIGINT)
 *
 * NOTE: Looks up the producer_reward_operation in the block to extract
 *       the vesting_shares amount.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.get_producer_reward(_block_num INT)
RETURNS BIGINT
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  __op_producer_reward INT := hafbe_backend.op_producer_reward();
BEGIN
  RETURN (ov.body_value -> 'vesting_shares' ->> 'amount')::BIGINT
  FROM hive.operations_view ov
  WHERE ov.block_num = _block_num
    AND ov.op_type_id = __op_producer_reward;
END
$$;

/*
 * get_block_operation_aggregation: Retrieves operation counts per type for a block.
 *
 * PARAMETERS:
 *   _block_num - The block number to query
 *
 * RETURNS: Array of (op_type_id, op_count) tuples for all operation types in the block
 *
 * USAGE: Used by get_block endpoint to show operation breakdown.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.get_block_operation_aggregation(_block_num INT)
RETURNS hafbe_backend.block_operations[]
LANGUAGE 'plpgsql'
STABLE
AS
$$
BEGIN
  RETURN array_agg((op_type_id, op_count)::hafbe_backend.block_operations)
  FROM hafbe_app.block_operations
  WHERE block_num = _block_num;
END
$$;

/*
 * build_json_for_single_operation: Creates operation array for single operation response.
 *
 * PARAMETERS:
 *   _op_type_id - The operation type ID
 *   _op_count   - The operation count
 *
 * RETURNS: Single-element array of (op_type_id, op_count)
 *
 * USAGE: Helper for building consistent response format.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.build_json_for_single_operation(
    _op_type_id INT,
    _op_count   INT
)
RETURNS hafbe_backend.block_operations[]
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
BEGIN
  RETURN ARRAY[(_op_type_id, _op_count)];
END
$$;

/*
 * get_trx_count: Counts the number of transactions in a specific block.
 *
 * PARAMETERS:
 *   _block_num - The block number to query
 *
 * RETURNS: Number of transactions in the block
 */
CREATE OR REPLACE FUNCTION hafbe_backend.get_trx_count(_block_num INT)
RETURNS INT
LANGUAGE 'plpgsql'
STABLE
AS
$$
BEGIN
  RETURN COUNT(*)
  FROM hive.transactions_view
  WHERE block_num = _block_num;
END
$$;

-- ============================================================================
-- SECTION 2: Filter Return Types  -- MOVED
-- ============================================================================
-- The composite types this file's functions return now live in
-- backend/types/blocksearch.sql, which install_app.sh applies first.
--
-- They were moved because re-creating a type needs DROP TYPE ... CASCADE, and that
-- CASCADE also dropped the eight gatherers in
-- backend/endpoint_helpers/blocksearch_filters.sql -- a file NOT re-applied by a partial
-- hot-patch of this one, leaving /block-search returning HTTP 500. Keeping the DROPs out
-- of this file makes re-applying it safe on its own.
-- ============================================================================

-- ============================================================================
-- SECTION 3: Range Calculation Functions
-- ============================================================================
-- Functions that calculate and normalize block ranges for queries.
-- Handle NULL inputs by using defaults (genesis or current head).
-- ============================================================================

/*
 * blocksearch_no_filter_count: Calculates block count without any operation filter.
 *
 * Simply counts blocks in the range. Used when no operation type filter is applied.
 *
 * PARAMETERS:
 *   _from          - Starting block (NULL = genesis block)
 *   _to            - Ending block (NULL = current head)
 *   _current_block - Current head block number
 *
 * RETURNS: blocksearch_filter_return with count and normalized range
 *
 * FORMULA: count = to - from + 1
 */
CREATE OR REPLACE FUNCTION hafbe_backend.blocksearch_no_filter_count(
    _from          INT,
    _to            INT,
    _current_block INT
)
RETURNS hafbe_backend.blocksearch_filter_return
LANGUAGE 'plpgsql'
IMMUTABLE
SET JIT = OFF
AS
$$
DECLARE
  __genesis_block INT := hafbe_backend.genesis_block_num();
  __to            INT;
  __from          INT;
  __count         INT;
BEGIN
  -- Normalize _to: use current_block if NULL or if requested block exceeds current
  __to := CASE
    WHEN _to IS NULL THEN _current_block
    WHEN _current_block < _to THEN _current_block
    ELSE _to
  END;

  -- Normalize _from: use genesis if NULL
  __from := CASE
    WHEN _from IS NULL THEN __genesis_block
    ELSE _from
  END;

  __count := __to - __from + 1;

  RETURN (__count, __from, __to)::hafbe_backend.blocksearch_filter_return;
END
$$;

/*
 * blocksearch_range: Calculates normalized block range without counting.
 *
 * Returns NULL for count - used when count will be determined separately
 * (e.g., by operation filter).
 *
 * PARAMETERS:
 *   _from          - Starting block (NULL = genesis block)
 *   _to            - Ending block (NULL = current head)
 *   _current_block - Current head block number
 *
 * RETURNS: blocksearch_filter_return with NULL count and normalized range
 */
CREATE OR REPLACE FUNCTION hafbe_backend.blocksearch_range(
    _from          INT,
    _to            INT,
    _current_block INT
)
RETURNS hafbe_backend.blocksearch_filter_return
LANGUAGE 'plpgsql'
IMMUTABLE
SET JIT = OFF
AS
$$
DECLARE
  __genesis_block INT := hafbe_backend.genesis_block_num();
  __to            INT;
  __from          INT;
BEGIN
  -- Normalize _to: use current_block if NULL or if requested block exceeds current
  __to := CASE
    WHEN _to IS NULL THEN _current_block
    WHEN _current_block < _to THEN _current_block
    ELSE _to
  END;

  -- Normalize _from: use genesis if NULL
  __from := CASE
    WHEN _from IS NULL THEN __genesis_block
    ELSE _from
  END;

  RETURN (NULL, __from, __to)::hafbe_backend.blocksearch_filter_return;
END
$$;

/*
 * aggregation_time_range: Resolve a (granularity, block-range) request into the
 * period-truncated [from_ts, to_ts] window the time-series aggregation operates over
 * (blocksearch_range + each boundary block's created_at, truncated to the period).
 *
 * current_block is passed IN (not read here) so the endpoint reads it ONCE, guaranteeing
 * the window cannot shift if a block is committed mid-request. Cheap: normalize + two
 * block look-ups.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.aggregation_time_range(
    _granularity   hafbe_backend.granularity,
    _from_block    INT,
    _to_block      INT,
    _current_block INT,
    OUT from_ts    TIMESTAMP,
    OUT to_ts      TIMESTAMP
)
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  __from        INT;
  __to          INT;
  __granularity TEXT := (
    CASE
      WHEN _granularity = 'daily'   THEN 'day'
      WHEN _granularity = 'monthly' THEN 'month'
      WHEN _granularity = 'yearly'  THEN 'year'
      ELSE NULL
    END
  );
BEGIN
  SELECT from_block, to_block
  INTO __from, __to
  FROM hafbe_backend.blocksearch_range(_from_block, _to_block, _current_block);

  from_ts := DATE_TRUNC(__granularity, (SELECT b.created_at FROM hive.blocks_view b WHERE b.num = __from)::TIMESTAMP);
  to_ts   := DATE_TRUNC(__granularity, (SELECT b.created_at FROM hive.blocks_view b WHERE b.num = __to)::TIMESTAMP);
END
$$;

-- aggregation_period_count() drove total_pages for the paginated stats endpoints (!494).
-- Pagination is gone (issue #139) and nothing else calls it, so drop it on redeploy.
DROP FUNCTION IF EXISTS hafbe_backend.aggregation_period_count(hafbe_backend.granularity, TIMESTAMP, TIMESTAMP);
DROP FUNCTION IF EXISTS hafbe_backend.aggregation_period_count(hafbe_backend.granularity, INT, INT);

/*
 * aggregation_default_from: Lower bound a time-series endpoint should actually use.
 *
 * When the caller supplied no from-block, an unbounded daily series spans the whole chain
 * (~3.7k periods). That is fine for one row per period, but the operation-type histogram
 * carries a nested per-op-type array per period and reaches ~6.6 MB, which trips client
 * timeouts -- the original report in issue #139. So an OMITTED lower bound falls back to
 * default_stats_window() before "now", exactly like the network statistics endpoints do.
 *
 * Deliberately narrow:
 *   - only when _from_omitted; an explicit from-block is always honoured in full, because
 *     charts need every period of the range they asked for (block_explorer_ui#759).
 *   - only at 'daily'; monthly (~125 periods) and yearly (~11) are small, and defaulting
 *     them would silently collapse the Explorer's all-time chart to a single bar.
 *
 * Pure function of its arguments so it can be unit-tested with synthetic timestamps -- the
 * 5M-block CI dataset spans <1 year, so the fallback never fires there.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.aggregation_default_from(
    _granularity   hafbe_backend.granularity,
    _from_ts       TIMESTAMP,
    _to_ts         TIMESTAMP,
    _from_omitted  BOOLEAN
)
RETURNS TIMESTAMP
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
BEGIN
  IF NOT COALESCE(_from_omitted, FALSE) OR _granularity IS DISTINCT FROM 'daily' THEN
    RETURN _from_ts;
  END IF;

  -- GREATEST keeps genesis when the chain is younger than the window.
  RETURN GREATEST(_from_ts, DATE_TRUNC('day', _to_ts - hafbe_backend.default_stats_window()));
END
$$;

/*
 * blocksearch_account_range: Calculates block and sequence range for account-based search.
 *
 * In addition to block range, calculates the account operation sequence numbers
 * for the first and last operations within the range.
 *
 * PARAMETERS:
 *   _account_id    - Account ID to search for
 *   _from          - Starting block (NULL = genesis block)
 *   _to            - Ending block (NULL = current head)
 *   _current_block - Current head block number
 *
 * RETURNS: blocksearch_account_filter_return with block range and sequence range
 */
CREATE OR REPLACE FUNCTION hafbe_backend.blocksearch_account_range(
    _account_id    INT,
    _from          INT,
    _to            INT,
    _current_block INT
)
RETURNS hafbe_backend.blocksearch_account_filter_return
LANGUAGE 'plpgsql'
STABLE
SET JIT = OFF
AS
$$
DECLARE
  __genesis_block INT := hafbe_backend.genesis_block_num();
  __to            INT;
  __from          INT;
  __to_seq        INT;
  __from_seq      INT;
BEGIN
  -- Normalize _to: use current_block if NULL or if requested block exceeds current
  __to := CASE
    WHEN _to IS NULL THEN _current_block
    WHEN _current_block < _to THEN _current_block
    ELSE _to
  END;

  -- Normalize _from: use genesis if NULL
  __from := CASE
    WHEN _from IS NULL THEN __genesis_block
    ELSE _from
  END;

  -- Find the last operation sequence number at or before __to
  __to_seq := (
    SELECT aov.account_op_seq_no
    FROM hive.account_operations_view aov
    WHERE aov.account_id = _account_id
      AND aov.block_num <= __to
    ORDER BY aov.account_op_seq_no DESC
    LIMIT 1
  );

  -- Find the first operation sequence number at or after __from
  __from_seq := (
    SELECT aov.account_op_seq_no
    FROM hive.account_operations_view aov
    WHERE aov.account_id = _account_id
      AND aov.block_num >= __from
    ORDER BY aov.account_op_seq_no ASC
    LIMIT 1
  );

  RETURN (__from, __to, __from_seq, __to_seq)::hafbe_backend.blocksearch_account_filter_return;
END
$$;

/*
 * blocksearch_by_op_count: Counts blocks containing a specific operation type.
 *
 * Used when filtering by operation type to determine pagination.
 * Limited to max_page_count * limit blocks to prevent unbounded queries.
 *
 * PARAMETERS:
 *   _operation     - Operation type ID to filter by
 *   _from          - Starting block (NULL = genesis block)
 *   _to            - Ending block (NULL = current head)
 *   _current_block - Current head block number
 *   _order_is      - Sort direction ('asc' or 'desc')
 *   _limit         - Page size
 *
 * RETURNS: blocksearch_filter_return with count (limited) and normalized range
 */
CREATE OR REPLACE FUNCTION hafbe_backend.blocksearch_by_op_count(
    _operation     INT,
    _from          INT,
    _to            INT,
    _current_block INT,
    _order_is      hafbe_backend.sort_direction,
    _limit         INT
)
RETURNS hafbe_backend.blocksearch_filter_return
LANGUAGE 'plpgsql'
STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET JIT = OFF
AS
$$
DECLARE
  __genesis_block  INT := hafbe_backend.genesis_block_num();
  __max_page_count INT := hafbe_backend.default_max_page_count();
  __to             INT;
  __from           INT;
BEGIN
  -- Normalize _to: use current_block if NULL or if requested block exceeds current
  __to := CASE
    WHEN _to IS NULL THEN _current_block
    WHEN _current_block < _to THEN _current_block
    ELSE _to
  END;

  -- Normalize _from: use genesis if NULL
  __from := CASE
    WHEN _from IS NULL THEN __genesis_block
    ELSE _from
  END;

  RETURN (
    WITH blocks AS (
      SELECT COUNT(*) AS count_blocks
      FROM (
        SELECT *
        FROM hafbe_app.block_operations ov
        WHERE ov.op_type_id = _operation
          AND ov.block_num <= __to
          AND ov.block_num >= __from
        ORDER BY
          (CASE WHEN _order_is = 'desc' THEN ov.block_num ELSE NULL END) DESC,
          (CASE WHEN _order_is = 'asc' THEN ov.block_num ELSE NULL END) ASC
        -- Limit to max_page_count pages to prevent unbounded queries
        LIMIT (__max_page_count * _limit)
      )
    )
    SELECT (count_blocks, __from, __to)::hafbe_backend.blocksearch_filter_return
    FROM blocks
  );
END
$$;

-- ============================================================================
-- SECTION 4: Pagination Functions
-- ============================================================================
-- Functions for calculating pagination parameters.
-- ============================================================================

/*
 * blocksearch_calculate_pages: Calculates pagination parameters for block search.
 *
 * Handles the complexity of pagination with both ascending and descending order,
 * including partial pages at the boundaries.
 *
 * PARAMETERS:
 *   _count    - Total number of items
 *   _page     - Requested page number (1-based)
 *   _order_is - Sort direction ('asc' or 'desc')
 *   _limit    - Page size
 *
 * RETURNS: calculate_pages_return with all pagination parameters
 *
 * PAGINATION LOGIC:
 *   For 'desc' order, page 1 is the LAST page (most recent blocks).
 *   For 'asc' order, page 1 is the FIRST page (oldest blocks).
 *
 *   When total count is not evenly divisible by page size:
 *   - For 'desc': page 1 gets the smaller "remainder" page
 *   - For 'asc': last page gets the smaller "remainder" page
 */
CREATE OR REPLACE FUNCTION hafbe_backend.blocksearch_calculate_pages(
    _count    INT,
    _page     INT,
    _order_is hafbe_backend.sort_direction,
    _limit    INT
)
RETURNS hafbe_backend.calculate_pages_return
LANGUAGE 'plpgsql'
STABLE
SET JIT = OFF
AS
$$
DECLARE
  __rest_of_division INT;
  __total_pages      INT;
  __page             INT;
  __offset           INT;
  __limit            INT;
BEGIN
  -- Handle zero count case early
  IF _count = 0 OR _count IS NULL THEN
    RETURN (0, 0, 0, 0, _limit)::hafbe_backend.calculate_pages_return;
  END IF;

  __rest_of_division := (_count % _limit)::INT;

  __total_pages := CASE
    WHEN __rest_of_division = 0 THEN _count / _limit
    ELSE (_count / _limit) + 1
  END::INT;

  -- Reject an out-of-range page BEFORE any page arithmetic. This guard used to run at the
  -- very end, after __page/__offset had already been computed -- too late: a page far past
  -- the end overflows the INT offset ((_page - 1) * _limit) and raises "integer out of
  -- range" (HTTP 500) instead of the intended 400, and in 'desc' order __page goes negative
  -- (__total_pages - _page + 1), producing a negative OFFSET. Validating first makes both
  -- impossible: past this point _page <= __total_pages, so the arithmetic below is bounded
  -- by _count and __page stays >= 1.
  PERFORM hafah_backend.validate_page(_page, __total_pages);

  -- Adjust page number for descending order (page 1 = most recent)
  __page := CASE
    WHEN _page IS NULL THEN 1
    WHEN _page IS NOT NULL AND _order_is = 'desc' THEN __total_pages - _page + 1
    ELSE _page
  END;

  -- Calculate offset accounting for partial pages
  __offset := CASE
    WHEN _order_is = 'desc' AND __page != 1 AND __rest_of_division != 0 THEN
      ((__page - 2) * _limit) + __rest_of_division
    WHEN __page = 1 THEN 0
    ELSE (__page - 1) * _limit
  END;

  -- Calculate limit accounting for partial pages
  __limit := CASE
    WHEN _order_is = 'desc' AND __page = 1 AND __rest_of_division != 0 THEN
      __rest_of_division
    WHEN _order_is = 'asc' AND __page = __total_pages AND __rest_of_division != 0 THEN
      __rest_of_division
    ELSE _limit
  END;

  RETURN (__rest_of_division, __total_pages, __page, __offset, __limit)::hafbe_backend.calculate_pages_return;
END
$$;

-- ============================================================================
-- SECTION 5: Block Search Functions
-- ============================================================================
-- Functions for finding blocks matching specific criteria.
-- ============================================================================

/*
 * find_blocks_with_op: Finds blocks containing a specific operation type.
 *
 * Returns blocks in the specified range that contain at least one operation
 * of the given type, along with the count of operations in each block.
 *
 * PARAMETERS:
 *   _operation - Operation type ID to search for
 *   _from      - Starting block number
 *   _to        - Ending block number
 *   _order_is  - Sort direction ('asc' or 'desc')
 *   _limit     - Maximum number of results
 *
 * RETURNS: Set of (block_num, op_type_id, op_count) rows
 */
CREATE OR REPLACE FUNCTION hafbe_backend.find_blocks_with_op(
    _operation INT,
    _from      INT,
    _to        INT,
    _order_is  hafbe_backend.sort_direction,
    _limit     INT
)
RETURNS SETOF hafbe_backend.find_blocks_with_op_return
LANGUAGE 'plpgsql'
STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET JIT = OFF
AS
$$
BEGIN
  RETURN QUERY (
    SELECT
      bo.block_num,
      bo.op_type_id,
      bo.op_count
    FROM hafbe_app.block_operations bo
    WHERE bo.op_type_id = _operation
      AND bo.block_num >= _from
      AND bo.block_num <= _to
    ORDER BY
      (CASE WHEN _order_is = 'desc' THEN bo.block_num ELSE NULL END) DESC,
      (CASE WHEN _order_is = 'asc' THEN bo.block_num ELSE NULL END) ASC
    LIMIT _limit
  );
END
$$;

/*
 * find_blocks_with_op_and_account: Finds blocks where an account has a specific operation.
 *
 * Searches the account_operations_view to find blocks where the specified
 * account participated in the given operation type.
 *
 * PARAMETERS:
 *   _operation  - Operation type ID to search for
 *   _account_id - Account ID to filter by
 *   _from       - Starting block number
 *   _to         - Ending block number
 *   _order_is   - Sort direction ('asc' or 'desc')
 *   _limit      - Maximum number of results
 *
 * RETURNS: Set of (block_num, op_type_id, NULL) rows
 *          Note: op_count is NULL since we're searching by account, not aggregating
 */
CREATE OR REPLACE FUNCTION hafbe_backend.find_blocks_with_op_and_account(
    _operation  INT,
    _account_id INT,
    _from       INT,
    _to         INT,
    _order_is   hafbe_backend.sort_direction,
    _limit      INT
)
RETURNS SETOF hafbe_backend.find_blocks_with_op_return
LANGUAGE 'plpgsql'
STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET JIT = OFF
AS
$$
BEGIN
  RETURN QUERY (
    SELECT
      aov.block_num,
      aov.op_type_id,
      NULL::INT
    FROM hive.account_operations_view aov
    WHERE aov.op_type_id = _operation
      AND aov.account_id = _account_id
      AND aov.block_num >= _from
      AND aov.block_num <= _to
    ORDER BY
      (CASE WHEN _order_is = 'desc' THEN aov.block_num ELSE NULL END) DESC,
      (CASE WHEN _order_is = 'asc' THEN aov.block_num ELSE NULL END) ASC
    LIMIT _limit
  );
END
$$;

-- ============================================================================
-- SECTION 6: Result Building Functions
-- ============================================================================
-- Functions for building final API responses from gatherer results.
-- ============================================================================

/*
 * blocksearch_build_result: Enriches gathered blocks and builds the final API response.
 *
 * This is the SINGLE point of enrichment for all block search filters.
 * It takes the intermediate gatherer_result and:
 *   1. Calculates the cursor (next from_block for pagination)
 *   2. Enriches each block with metadata from blocks_view
 *   3. Adds producer_reward, trx_count via helper functions
 *   4. Returns the final block_history response
 *
 * PARAMETERS:
 *   _gathered - The gatherer_result from any filter function
 *   _order_is - Sort direction ('asc' or 'desc')
 *
 * RETURNS: block_history with enriched block data
 *
 * CURSOR CALCULATION:
 *   The cursor indicates where to start the next paginated request.
 *   - NULL min_block_num: no results found, keep original range_from
 *   - min_block_num = 1: at genesis, cursor = 1
 *   - Not saturated (pre_grouped_count != max_page_limit): more data available, keep range_from
 *   - Saturated: results capped, cursor = min_block_num - 1 (start before current results)
 */
CREATE OR REPLACE FUNCTION hafbe_backend.blocksearch_build_result(
    _gathered hafbe_backend.gatherer_result,
    _order_is hafbe_backend.sort_direction
)
RETURNS hafbe_backend.block_history
LANGUAGE 'plpgsql'
STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET JIT = OFF
AS
$$
DECLARE
  __cursor_from INT;
  __result      hafbe_backend.blocksearch[];
BEGIN
  -- Handle empty result case
  IF _gathered.total_pages = 0 OR _gathered.blocks IS NULL OR array_length(_gathered.blocks, 1) IS NULL THEN
    RETURN (
      COALESCE(_gathered.total_count, 0),
      COALESCE(_gathered.total_pages, 0),
      (_gathered.range_from, _gathered.range_to)::hafbe_backend.block_range,
      '{}'::hafbe_backend.blocksearch[]
    )::hafbe_backend.block_history;
  END IF;

  -- Calculate cursor for next paginated request
  __cursor_from := CASE
    WHEN _gathered.min_block_num IS NULL THEN
      _gathered.range_from
    WHEN _gathered.min_block_num = 1 THEN
      1
    WHEN _gathered.pre_grouped_count != _gathered.max_page_limit THEN
      _gathered.range_from
    ELSE
      _gathered.min_block_num - 1
  END;

  -- Enrich blocks with metadata and build result array
  SELECT array_agg(row ORDER BY
    (CASE WHEN _order_is = 'desc' THEN row.block_num ELSE NULL END) DESC,
    (CASE WHEN _order_is = 'asc' THEN row.block_num ELSE NULL END) ASC
  )
  INTO __result
  FROM (
    SELECT
      g.block_num,
      bv.created_at,
      hafah_backend.get_account_name(bv.producer_account_id) AS producer_account,
      hafbe_backend.get_producer_reward(g.block_num)::TEXT AS producer_reward,
      hafbe_backend.get_trx_count(g.block_num) AS trx_count,
      encode(bv.hash, 'hex') AS hash,
      encode(bv.prev, 'hex') AS prev,
      g.operations
    FROM unnest(_gathered.blocks) AS g(block_num, operations)
    JOIN hive.blocks_view bv ON bv.num = g.block_num
  ) row;

  RETURN (
    COALESCE(_gathered.total_count, 0),
    COALESCE(_gathered.total_pages, 0),
    (__cursor_from, _gathered.range_to)::hafbe_backend.block_range,
    COALESCE(__result, '{}'::hafbe_backend.blocksearch[])
  )::hafbe_backend.block_history;
END
$$;

RESET ROLE;
