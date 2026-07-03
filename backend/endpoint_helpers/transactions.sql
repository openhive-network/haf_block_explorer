-- =============================================================================
-- Transaction Statistics Helper Functions
-- =============================================================================
-- Functions for retrieving and aggregating transaction statistics
-- at various granularities (daily, monthly, yearly).
-- =============================================================================

SET ROLE hafbe_owner;

-- =============================================================================
-- SECTION 1: Type Definitions
-- =============================================================================

-- NOTE: the public hafbe_backend.transaction_stats type -- and the paginated
-- hafbe_backend.transaction_stats_return wrapper that depends on it -- are
-- defined in endpoints/types/transactions.sql, which installs before this file.
-- transaction_stats is intentionally NOT redefined here: a DROP TYPE ... CASCADE
-- would strip the `stats` column off transaction_stats_return. Only the internal
-- trx_stats type (no OpenAPI schema, not depended on elsewhere) lives here.

/*
 * trx_stats: Transaction statistics for a time period (internal format).
 *
 * Similar to transaction_stats but with count_blocks instead of avg_trx.
 * Used for aggregation before calculating averages.
 *
 * FIELDS:
 *   date           - Period timestamp
 *   trx_count      - Total transactions in period
 *   count_blocks   - Number of blocks in period
 *   min_trx        - Minimum transactions in a single block
 *   max_trx        - Maximum transactions in a single block
 *   last_block_num - Last block number in the period
 */
DROP TYPE IF EXISTS hafbe_backend.trx_stats CASCADE;
CREATE TYPE hafbe_backend.trx_stats AS (
    date           TIMESTAMP,
    trx_count      INT,
    count_blocks   INT,
    min_trx        INT,
    max_trx        INT,
    last_block_num INT
);

-- =============================================================================
-- SECTION 2: Aggregation Helper Functions
-- =============================================================================

/*
 * transaction_stats_by_year: Aggregates monthly stats into yearly statistics.
 *
 * Reads from pre-computed monthly stats table and groups by year.
 * Used by get_transaction_stats when granularity is 'yearly'.
 *
 * PARAMETERS:
 *   _from - Start timestamp (truncated to year)
 *   _to   - End timestamp (truncated to year)
 *
 * RETURNS: Set of trx_stats records grouped by year
 */
CREATE OR REPLACE FUNCTION hafbe_backend.transaction_stats_by_year(
    _from TIMESTAMP,
    _to   TIMESTAMP
)
RETURNS SETOF hafbe_backend.trx_stats
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN QUERY
    WITH get_year AS (
      SELECT
        trx_count,
        count_blocks,
        min_trx,
        max_trx,
        last_block_num,
        updated_at,
        DATE_TRUNC('year', updated_at) AS by_year
      FROM hafbe_app.transaction_stats_by_month
      WHERE DATE_TRUNC('year', updated_at) BETWEEN _from AND _to
    )
    SELECT
      by_year,
      SUM(trx_count)::INT,
      SUM(count_blocks)::INT,
      MIN(min_trx)::INT,
      MAX(max_trx)::INT,
      MAX(last_block_num) AS last_block_num
    FROM get_year
    GROUP BY by_year;
END
$$;

/*
 * get_transaction_stats: Retrieves transaction stats at specified granularity.
 *
 * Dispatcher function that reads from the appropriate pre-computed stats table
 * based on the requested granularity.
 *
 * PARAMETERS:
 *   _granularity - Time granularity: 'daily', 'monthly', or 'yearly'
 *   _from        - Start timestamp
 *   _to          - End timestamp
 *
 * RETURNS: Set of trx_stats records for the time range
 *
 * DATA SOURCES:
 *   - daily:   hafbe_app.transaction_stats_by_day
 *   - monthly: hafbe_app.transaction_stats_by_month
 *   - yearly:  Computed from monthly via transaction_stats_by_year()
 */
CREATE OR REPLACE FUNCTION hafbe_backend.get_transaction_stats(
    _granularity hafbe_backend.granularity,
    _from        TIMESTAMP,
    _to          TIMESTAMP
)
RETURNS SETOF hafbe_backend.trx_stats
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  IF _granularity = 'daily' THEN
    RETURN QUERY
      SELECT
        bh.updated_at,
        bh.trx_count,
        bh.count_blocks,
        bh.min_trx,
        bh.max_trx,
        bh.last_block_num
      FROM hafbe_app.transaction_stats_by_day bh
      WHERE bh.updated_at BETWEEN _from AND _to;

  ELSIF _granularity = 'monthly' THEN
    RETURN QUERY
      SELECT
        bh.updated_at,
        bh.trx_count,
        bh.count_blocks,
        bh.min_trx,
        bh.max_trx,
        bh.last_block_num
      FROM hafbe_app.transaction_stats_by_month bh
      WHERE bh.updated_at BETWEEN _from AND _to;

  ELSIF _granularity = 'yearly' THEN
    RETURN QUERY
      SELECT
        bh.date,
        bh.trx_count,
        bh.count_blocks,
        bh.min_trx,
        bh.max_trx,
        bh.last_block_num
      FROM hafbe_backend.transaction_stats_by_year(_from, _to) bh;

  ELSE
    RAISE EXCEPTION 'Unsupported granularity: %', _granularity;
  END IF;
END
$$;

-- =============================================================================
-- SECTION 3: Main API Function
-- =============================================================================

/*
 * get_transaction_aggregation: Main function for transaction statistics API.
 *
 * Returns transaction statistics for a block range at the specified granularity.
 * Fills gaps in the time series with zero values for periods without data.
 *
 * PARAMETERS:
 *   _granularity - Time granularity: 'daily', 'monthly', or 'yearly'
 *   _direction   - Sort direction: 'asc' or 'desc'
 *   _from_block  - Starting block number (NULL = genesis)
 *   _to_block    - Ending block number (NULL = current head)
 *
 * RETURNS: Set of transaction_stats records covering the time range
 *
 * PROCESSING STEPS:
 *   1. Convert block range to timestamp range
 *   2. Generate complete time series for the period
 *   3. Left join with actual stats (gaps become NULL)
 *   4. Fill missing last_block_num by finding nearest block
 *   5. Calculate avg_trx from trx_count and count_blocks
 */
CREATE OR REPLACE FUNCTION hafbe_backend.get_transaction_aggregation(
    _granularity hafbe_backend.granularity,
    _direction   hafbe_backend.sort_direction,
    _from_block  INT,
    _to_block    INT,
    _page        INT DEFAULT 1,
    _page_size   INT DEFAULT 100
)
RETURNS SETOF hafbe_backend.transaction_stats
LANGUAGE 'plpgsql' STABLE
AS
$$
DECLARE
  __from                INT;
  __to                  INT;
  __full_from_timestamp TIMESTAMP;
  __full_to_timestamp   TIMESTAMP;
  __from_timestamp      TIMESTAMP;
  __to_timestamp        TIMESTAMP;
  __granularity         TEXT;
  __one_period          INTERVAL;
  __hafbe_current_block INT := (SELECT current_block_num FROM hafd.contexts WHERE name = 'hafbe_app');
BEGIN
  -- Convert granularity enum to PostgreSQL interval keyword
  __granularity := (
    CASE
      WHEN _granularity = 'daily'   THEN 'day'
      WHEN _granularity = 'monthly' THEN 'month'
      WHEN _granularity = 'yearly'  THEN 'year'
      ELSE NULL
    END
  );

  -- Normalize block range (block_num or timestamp -> block_num), then convert the
  -- boundaries to period-truncated timestamps. This is the full requested range;
  -- the page window is carved out of it below.
  SELECT from_block, to_block
  INTO __from, __to
  FROM hafbe_backend.blocksearch_range(_from_block, _to_block, __hafbe_current_block);

  __full_from_timestamp := DATE_TRUNC(__granularity, (SELECT b.created_at FROM hive.blocks_view b WHERE b.num = __from)::TIMESTAMP);
  __full_to_timestamp   := DATE_TRUNC(__granularity, (SELECT b.created_at FROM hive.blocks_view b WHERE b.num = __to)::TIMESTAMP);

  __one_period := ('1 ' || __granularity)::INTERVAL;

  -- Narrow the full range to the requested page's contiguous period window, so only
  -- page_size periods are generated and aggregated (bounds work AND payload). A slice
  -- of a regular series is contiguous, so [MIN,MAX] reproduces exactly the page.
  SELECT MIN(s.p), MAX(s.p)
  INTO __from_timestamp, __to_timestamp
  FROM (
    SELECT p
    FROM generate_series(__full_from_timestamp, __full_to_timestamp, __one_period) AS p
    ORDER BY
      (CASE WHEN _direction = 'desc' THEN p END) DESC,
      (CASE WHEN _direction = 'asc'  THEN p END) ASC
    OFFSET (GREATEST(_page, 1) - 1) * _page_size
    LIMIT _page_size
  ) s;

  RETURN QUERY (
    /*
     * =========================================================================
     * CTE: date_series
     * =========================================================================
     * PURPOSE: Generate complete time series for the requested range.
     *
     * Ensures we return a row for every period, even if no transactions
     * occurred during that time.
     */
    WITH date_series AS (
      SELECT generate_series(__from_timestamp, __to_timestamp, __one_period) AS date
    ),

    /*
     * =========================================================================
     * CTE: get_daily_aggregation
     * =========================================================================
     * WHY MATERIALIZED: Expensive query to pre-computed stats tables.
     *
     * PURPOSE: Fetch actual transaction statistics for the time range.
     */
    get_daily_aggregation AS MATERIALIZED (
      SELECT
        bh.date,
        bh.trx_count,
        bh.count_blocks,
        bh.min_trx,
        bh.max_trx,
        bh.last_block_num
      FROM hafbe_backend.get_transaction_stats(_granularity, __from_timestamp, __to_timestamp) bh
    ),

    /*
     * =========================================================================
     * CTE: transaction_records
     * =========================================================================
     * PURPOSE: Left join date series with actual data.
     *
     * Gaps in data (periods with no transactions) will have NULL values
     * which are replaced with 0/NULL as appropriate.
     */
    transaction_records AS (
      SELECT
        ds.date,
        COALESCE(bh.trx_count, 0)    AS trx_count,
        COALESCE(bh.count_blocks, 0) AS count_blocks,
        COALESCE(bh.min_trx, 0)      AS min_trx,
        COALESCE(bh.max_trx, 0)      AS max_trx,
        bh.last_block_num            AS last_block_num  -- NULL if no data
      FROM date_series ds
      LEFT JOIN get_daily_aggregation bh ON ds.date = bh.date
    ),

    /*
     * =========================================================================
     * CTE: join_missing_block
     * =========================================================================
     * PURPOSE: Fill in missing last_block_num for periods without transactions.
     *
     * Uses a LATERAL lookup for the last block at/before period end. This is exact
     * per period (a carry-forward from an earlier period would mis-report the block
     * for an empty interior period); it only fires for empty periods and is served by
     * hive_blocks_created_at_idx, so dense data does essentially no extra work.
     */
    join_missing_block AS (
      SELECT
        fb.date,
        fb.trx_count,
        fb.count_blocks,
        fb.min_trx,
        fb.max_trx,
        COALESCE(fb.last_block_num, jl.last_block_num) AS last_block_num
      FROM transaction_records fb
      LEFT JOIN LATERAL (
        SELECT b.num AS last_block_num
        FROM hive.blocks_view b
        WHERE b.created_at <= fb.date + __one_period
        ORDER BY b.created_at DESC
        LIMIT 1
      ) jl ON fb.last_block_num IS NULL
    )

    /*
     * Final projection:
     * - Adjust date to end of period (capped at current time)
     * - Calculate average from count (avoid division by zero)
     */
    SELECT
      LEAST(fb.date + __one_period, CURRENT_TIMESTAMP)::TIMESTAMP AS adjusted_date,
      fb.trx_count::INT,
      (CASE WHEN fb.count_blocks = 0 THEN 0 ELSE (fb.trx_count / fb.count_blocks) END)::INT AS avg_trx,
      fb.min_trx::INT,
      fb.max_trx::INT,
      fb.last_block_num::INT
    FROM join_missing_block fb
    ORDER BY
      (CASE WHEN _direction = 'desc' THEN fb.date ELSE NULL END) DESC,
      (CASE WHEN _direction = 'asc' THEN fb.date ELSE NULL END) ASC
  );
END
$$;

RESET ROLE;
