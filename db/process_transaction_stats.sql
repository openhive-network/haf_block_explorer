SET ROLE hafbe_owner;

/*
 * process_transaction_stats: Aggregates transaction counts by day and month.
 *
 * Core operations: Counts transactions per block, joins with block timestamps,
 * aggregates by day/month periods, and upserts into statistics tables.
 * Tracks sum, count, min, max for each time period.
 */
CREATE OR REPLACE FUNCTION hafbe_app.process_transaction_stats(_from INT, _to INT)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
SET enable_bitmapscan = OFF
AS $$
DECLARE
  __trx_by_day   INT;
  __trx_by_month INT;
BEGIN

  /*
   * ===================================================================================
   * SECTION 1: Data Gathering
   * ===================================================================================
   * Fetch transaction counts per block and join with block timestamps.
   */

  /*
   * ===================================================================================
   * CTE: gather_transactions
   * ===================================================================================
   * WHY MATERIALIZED: Expensive count aggregation, result used by join_blocks_date.
   *
   * PURPOSE: Count transactions per block in the processing range.
   *
   * DATA FLOW:
   *   1. Scans transactions_view for blocks in range
   *   2. Groups by block_num and counts transactions
   *
   * OUTPUT: One row per block with transaction count.
   */
  WITH gather_transactions AS MATERIALIZED (
    SELECT
      block_num,
      COUNT(*) AS trx_count
    FROM hafbe_app.transactions_view
    WHERE block_num BETWEEN _from AND _to
    GROUP BY block_num
  ),

  /*
   * ===================================================================================
   * CTE: join_blocks_date
   * ===================================================================================
   * WHY MATERIALIZED: JOIN result used by both group_by_day and group_by_month.
   *
   * PURPOSE: Attach day/month timestamps to each block's transaction count.
   *
   * DATA FLOW:
   *   1. Scans all blocks in range from blocks_view
   *   2. LEFT JOINs with gather_transactions (blocks with 0 transactions get COALESCE to 0)
   *   3. Extracts day and month from block timestamp
   *
   * OUTPUT: One row per block with trx_count, by_day, by_month.
   */
  join_blocks_date AS MATERIALIZED (
    SELECT
      bv.num                             AS block_num,
      COALESCE(gt.trx_count, 0)          AS trx_count,
      date_trunc('day', bv.created_at)   AS by_day,
      date_trunc('month', bv.created_at) AS by_month
    FROM hafbe_app.blocks_view bv
    LEFT JOIN gather_transactions gt ON gt.block_num = bv.num
    WHERE bv.num BETWEEN _from AND _to
  ),

  /*
   * ===================================================================================
   * SECTION 2: Time-Period Aggregation
   * ===================================================================================
   * Aggregate transaction statistics by day and month periods.
   */

  /*
   * ===================================================================================
   * CTE: group_by_day
   * ===================================================================================
   * PURPOSE: Aggregate transaction statistics for each day.
   *
   * OUTPUT: sum_trx, count_blocks, min_trx, max_trx, last_block per day.
   */
  group_by_day AS (
    SELECT
      SUM(trx_count)::INT AS sum_trx,
      COUNT(*)::INT       AS count_blocks,
      MIN(trx_count)::INT AS min_trx,
      MAX(trx_count)::INT AS max_trx,
      MAX(block_num)::INT AS trx_block,
      by_day
    FROM join_blocks_date
    GROUP BY by_day
    ORDER BY by_day
  ),

  /*
   * ===================================================================================
   * CTE: group_by_month
   * ===================================================================================
   * PURPOSE: Aggregate transaction statistics for each month.
   *
   * OUTPUT: sum_trx, count_blocks, min_trx, max_trx, last_block per month.
   */
  group_by_month AS (
    SELECT
      SUM(trx_count)::INT AS sum_trx,
      COUNT(*)::INT       AS count_blocks,
      MIN(trx_count)::INT AS min_trx,
      MAX(trx_count)::INT AS max_trx,
      MAX(block_num)::INT AS trx_block,
      by_month
    FROM join_blocks_date
    GROUP BY by_month
    ORDER BY by_month
  ),

  /*
   * ===================================================================================
   * SECTION 3: Upsert Statistics
   * ===================================================================================
   * Insert or update statistics tables with aggregated data.
   *
   * ADDITIVE UPSERT PATTERN:
   *   trx_count    = trx_agg.trx_count + EXCLUDED.trx_count
   *   count_blocks = trx_agg.count_blocks + EXCLUDED.count_blocks
   *   Accumulates counts across processing batches.
   *
   * MIN/MAX TRACKING PATTERN:
   *   min_trx = LEAST(EXCLUDED.min_trx, trx_agg.min_trx)
   *   max_trx = GREATEST(EXCLUDED.max_trx, trx_agg.max_trx)
   *   Maintains true min/max across all batches.
   */

  /*
   * ===================================================================================
   * CTE: insert_trx_stats_by_day
   * ===================================================================================
   * PURPOSE: Upsert daily transaction statistics.
   */
  insert_trx_stats_by_day AS (
    INSERT INTO hafbe_app.transaction_stats_by_day AS trx_agg
      (trx_count, count_blocks, min_trx, max_trx, last_block_num, updated_at)
    SELECT
      sum_trx,
      count_blocks,
      min_trx,
      max_trx,
      trx_block,
      by_day
    FROM group_by_day
    ON CONFLICT ON CONSTRAINT pk_transaction_stats_by_day DO UPDATE SET
      trx_count      = trx_agg.trx_count + EXCLUDED.trx_count,
      count_blocks   = trx_agg.count_blocks + EXCLUDED.count_blocks,
      min_trx        = LEAST(EXCLUDED.min_trx, trx_agg.min_trx)::INT,
      max_trx        = GREATEST(EXCLUDED.max_trx, trx_agg.max_trx)::INT,
      last_block_num = EXCLUDED.last_block_num
    RETURNING (xmax = 0) AS is_new_entry, trx_agg.updated_at
  ),

  /*
   * ===================================================================================
   * CTE: insert_trx_stats_by_month
   * ===================================================================================
   * PURPOSE: Upsert monthly transaction statistics.
   */
  insert_trx_stats_by_month AS (
    INSERT INTO hafbe_app.transaction_stats_by_month AS trx_agg
      (trx_count, count_blocks, min_trx, max_trx, last_block_num, updated_at)
    SELECT
      sum_trx,
      count_blocks,
      min_trx,
      max_trx,
      trx_block,
      by_month
    FROM group_by_month
    ON CONFLICT ON CONSTRAINT pk_transaction_stats_by_month DO UPDATE SET
      trx_count      = trx_agg.trx_count + EXCLUDED.trx_count,
      count_blocks   = trx_agg.count_blocks + EXCLUDED.count_blocks,
      min_trx        = LEAST(EXCLUDED.min_trx, trx_agg.min_trx)::INT,
      max_trx        = GREATEST(EXCLUDED.max_trx, trx_agg.max_trx)::INT,
      last_block_num = EXCLUDED.last_block_num
    RETURNING (xmax = 0) AS is_new_entry, trx_agg.updated_at
  )

  SELECT
    (SELECT COUNT(*) FROM insert_trx_stats_by_day)   AS by_day,
    (SELECT COUNT(*) FROM insert_trx_stats_by_month) AS by_month
  INTO __trx_by_day, __trx_by_month;

END $$;

RESET ROLE;
