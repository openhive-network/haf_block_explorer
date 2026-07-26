-- =============================================================================
-- Operation Type Statistics Helper Functions
-- =============================================================================
-- Functions for retrieving and aggregating per-op-type operation counts
-- at various granularities (daily, monthly, yearly), joined with
-- transaction totals from hafbe_app.transaction_stats_by_day/_by_month.
--
-- Mirrors backend/endpoint_helpers/transactions.sql structure.
-- =============================================================================

SET ROLE hafbe_owner;

-- =============================================================================
-- SECTION 1: Internal flat row type (per-period scalar fields, no nested ops)
-- =============================================================================

/*
 * op_stats_flat: Flat per-period aggregate. Internal use only; the public
 * endpoint type hafbe_backend.operation_type_stats holds the nested
 * `operations` array assembled from this flat form via array_agg.
 */
DROP TYPE IF EXISTS hafbe_backend.op_stats_flat CASCADE;
CREATE TYPE hafbe_backend.op_stats_flat AS (
    date           TIMESTAMP,
    op_type_id     INT,
    op_count       BIGINT,
    last_block_num INT
);

-- =============================================================================
-- SECTION 2: Aggregation Helper Functions
-- =============================================================================

/*
 * operation_type_stats_by_year: Aggregates monthly per-op-type stats into yearly.
 *
 * Reads pre-computed monthly per-op-type stats and groups by year.
 * Used by get_operation_type_stats when granularity is 'yearly'.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.operation_type_stats_by_year(
    _from     TIMESTAMP,
    _to       TIMESTAMP,
    _op_types INT[] DEFAULT NULL
)
RETURNS SETOF hafbe_backend.op_stats_flat
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN QUERY
    SELECT
      DATE_TRUNC('year', s.updated_at)::TIMESTAMP AS date,
      s.op_type_id::INT,
      SUM(s.op_count)::BIGINT       AS op_count,
      MAX(s.last_block_num)::INT    AS last_block_num
    FROM hafbe_app.operation_type_stats_by_month s
    WHERE DATE_TRUNC('year', s.updated_at) BETWEEN _from AND _to
      AND (_op_types IS NULL OR s.op_type_id = ANY(_op_types))
    GROUP BY DATE_TRUNC('year', s.updated_at), s.op_type_id;
END
$$;

/*
 * get_operation_type_stats: Retrieves per-op-type counts at specified granularity.
 *
 * Dispatcher function that reads from the appropriate pre-computed table
 * based on the requested granularity.
 *
 * DATA SOURCES:
 *   - daily:   hafbe_app.operation_type_stats_by_day
 *   - monthly: hafbe_app.operation_type_stats_by_month
 *   - yearly:  Computed from monthly via operation_type_stats_by_year()
 */
CREATE OR REPLACE FUNCTION hafbe_backend.get_operation_type_stats(
    _granularity hafbe_backend.granularity,
    _from        TIMESTAMP,
    _to          TIMESTAMP,
    _op_types    INT[] DEFAULT NULL
)
RETURNS SETOF hafbe_backend.op_stats_flat
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  IF _granularity = 'daily' THEN
    RETURN QUERY
      SELECT
        s.updated_at,
        s.op_type_id::INT,
        s.op_count,
        s.last_block_num
      FROM hafbe_app.operation_type_stats_by_day s
      WHERE s.updated_at BETWEEN _from AND _to
        AND (_op_types IS NULL OR s.op_type_id = ANY(_op_types));

  ELSIF _granularity = 'monthly' THEN
    RETURN QUERY
      SELECT
        s.updated_at,
        s.op_type_id::INT,
        s.op_count,
        s.last_block_num
      FROM hafbe_app.operation_type_stats_by_month s
      WHERE s.updated_at BETWEEN _from AND _to
        AND (_op_types IS NULL OR s.op_type_id = ANY(_op_types));

  ELSIF _granularity = 'yearly' THEN
    RETURN QUERY
      SELECT *
      FROM hafbe_backend.operation_type_stats_by_year(_from, _to, _op_types);

  ELSE
    RAISE EXCEPTION 'Unsupported granularity: %', _granularity;
  END IF;
END
$$;

-- =============================================================================
-- SECTION 3: Main API Function
-- =============================================================================

/*
 * get_operation_type_aggregation: Main function for the operation-type-statistics endpoint.
 *
 * Returns one row per period in the [_full_from_timestamp, _full_to_timestamp] range at
 * the requested granularity. Each row contains:
 *   - total_transactions (from transaction_stats_by_day/month rollup)
 *   - total_operations   (sum across op-type breakdown for that period)
 *   - operations         (nested array of {op_type_id, op_count})
 *   - last_block_num
 *
 * Periods with no data still appear (empty operations array, total_*=0). The
 * `date` is adjusted to end-of-period (capped at CURRENT_TIMESTAMP for the
 * in-progress period) to match the convention of get_transaction_aggregation.
 *
 * PARAMETERS:
 *   _granularity     - 'daily' | 'monthly' | 'yearly'
 *   _from_timestamp  - lower bound of the range, period-truncated (from aggregation_time_range)
 *   _to_timestamp    - upper bound of the range, period-truncated (from aggregation_time_range)
 *   _op_types        - optional filter; NULL = include all op_type_ids
 *
 * NOTE: unlike get_transaction_aggregation this emits a nested per-op-type array per
 * period, so an unbounded daily range is ~6.6 MB. The caller bounds an omitted range to
 * hafbe_backend.default_stats_window() rather than paginating here (issue #139).
 */
-- Every signature this function has ever shipped with, so hot-patching THIS FILE ALONE
-- cannot leave a stale overload behind. (Redundant on a full install: the DROP TYPE ...
-- CASCADE in endpoints/types/transactions.sql, applied earlier, already removed them all.)
--   ..., TIMESTAMP, TIMESTAMP, INT, INT, INT[]  -- !494, paginated
--   ..., INT, INT, INT[]                        -- pre-!494, block-number range
--   ..., TIMESTAMP, TIMESTAMP, INT[]            -- this MR, before _direction was dropped
DROP FUNCTION IF EXISTS hafbe_backend.get_operation_type_aggregation(hafbe_backend.granularity, hafbe_backend.sort_direction, TIMESTAMP, TIMESTAMP, INT, INT, INT[]);
DROP FUNCTION IF EXISTS hafbe_backend.get_operation_type_aggregation(hafbe_backend.granularity, hafbe_backend.sort_direction, TIMESTAMP, TIMESTAMP, INT[]);
DROP FUNCTION IF EXISTS hafbe_backend.get_operation_type_aggregation(hafbe_backend.granularity, hafbe_backend.sort_direction, INT, INT, INT[]);
CREATE OR REPLACE FUNCTION hafbe_backend.get_operation_type_aggregation(
    _granularity     hafbe_backend.granularity,
    _from_timestamp  TIMESTAMP,
    _to_timestamp    TIMESTAMP,
    _op_types        INT[] DEFAULT NULL
)
RETURNS SETOF hafbe_backend.operation_type_stats
LANGUAGE 'plpgsql' STABLE
AS
$$
DECLARE
  __granularity         TEXT;
  __one_period          INTERVAL;
BEGIN
  __granularity := (
    CASE
      WHEN _granularity = 'daily'   THEN 'day'
      WHEN _granularity = 'monthly' THEN 'month'
      WHEN _granularity = 'yearly'  THEN 'year'
      ELSE NULL
    END
  );

  __one_period := ('1 ' || __granularity)::INTERVAL;

  RETURN QUERY (
    /*
     * Complete period series for the requested window, so periods with no
     * data still appear as a row in the response.
     */
    WITH date_series AS (
      SELECT generate_series(_from_timestamp, _to_timestamp, __one_period) AS period
    ),

    /*
     * Flat per-(period, op_type_id) rows from the appropriate pre-aggregate.
     */
    op_stats AS MATERIALIZED (
      SELECT s.date AS period, s.op_type_id, s.op_count, s.last_block_num
      FROM hafbe_backend.get_operation_type_stats(_granularity, _from_timestamp, _to_timestamp, _op_types) s
    ),

    /*
     * Roll the flat per-op-type rows up into one row per period:
     *   - operations: array of (op_type_id, op_count)
     *   - total_operations: sum across the array
     *   - last_block_num: max across the array
     */
    period_ops AS (
      SELECT
        os.period,
        SUM(os.op_count)::BIGINT AS total_operations,
        ARRAY_AGG(
          ROW(os.op_type_id, os.op_count)::hafbe_backend.period_op_type_count
          ORDER BY os.op_type_id
        ) AS operations,
        MAX(os.last_block_num)::INT AS last_block_num
      FROM op_stats os
      GROUP BY os.period
    ),

    /*
     * Transaction totals for the same periods. Granularity dispatch:
     *   daily/monthly  -> read directly from transaction_stats_by_day/_by_month
     *   yearly         -> aggregate from monthly
     */
    trx_stats AS MATERIALIZED (
      SELECT
        ts.date::TIMESTAMP AS period,
        ts.trx_count::BIGINT AS trx_count,
        ts.last_block_num
      FROM hafbe_backend.get_transaction_stats(_granularity, _from_timestamp, _to_timestamp) ts
    ),

    /*
     * Final assembly: LEFT JOIN keeps every period from the series, even
     * if op-type rollup or trx rollup happens to be empty for it.
     */
    assembled AS (
      SELECT
        ds.period,
        COALESCE(ts.trx_count, 0)        AS total_transactions,
        COALESCE(po.total_operations, 0) AS total_operations,
        COALESCE(po.operations, ARRAY[]::hafbe_backend.period_op_type_count[]) AS operations,
        COALESCE(po.last_block_num, ts.last_block_num) AS last_block_num
      FROM date_series ds
      LEFT JOIN period_ops po ON po.period = ds.period
      LEFT JOIN trx_stats  ts ON ts.period = ds.period
    ),

    /*
     * Fill in last_block_num for periods where both rollups were empty, using a
     * lateral lookup for the last block at/before period end. This is exact per
     * period (a carry-forward from an earlier period would mis-report the block for
     * an empty interior period); it only fires for empty periods and is served by
     * hive_blocks_created_at_idx, so a full-history request with dense data does
     * essentially no extra work.
     */
    with_block AS (
      SELECT
        a.period,
        a.total_transactions,
        a.total_operations,
        a.operations,
        COALESCE(a.last_block_num, jl.last_block_num) AS last_block_num
      FROM assembled a
      LEFT JOIN LATERAL (
        SELECT b.num AS last_block_num
        FROM hive.blocks_view b
        WHERE b.created_at <= a.period + __one_period
        ORDER BY b.created_at DESC
        LIMIT 1
      ) jl ON a.last_block_num IS NULL
    )

    SELECT
      LEAST(wb.period + __one_period, CURRENT_TIMESTAMP)::TIMESTAMP AS date,
      wb.total_transactions,
      wb.total_operations,
      wb.operations,
      wb.last_block_num
    FROM with_block wb
    -- Deliberately unordered: the caller applies the single authoritative ORDER BY. Sorting
    -- here as well meant a second full sort of ~3.7k rows each carrying a nested array.
  );
END
$$;

RESET ROLE;
