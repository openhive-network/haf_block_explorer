SET ROLE hafbe_owner;

/*
 * process_block_operations: Aggregates operation counts per block/type and rolls them
 * up to per-day and per-month per-op-type stats in the same scan.
 *
 * Three sinks, fed by a single MATERIALIZED CTE over hafbe_app.operations_view:
 *   1. hafbe_app.block_operations              -- one row per (block_num, op_type_id)
 *   2. hafbe_app.operation_type_stats_by_day   -- one row per (day,   op_type_id)
 *   3. hafbe_app.operation_type_stats_by_month -- one row per (month, op_type_id)
 *
 * Combining all three here avoids re-reading freshly-inserted block_operations rows
 * in a follow-up processor (which would seq-scan during MASSIVE sync, before the
 * block_operations indexes exist) and keeps a single pass over operations_view.
 *
 * Daily/monthly stats use additive upsert so counts accumulate across MASSIVE batches.
 */
CREATE OR REPLACE FUNCTION hafbe_app.process_block_operations(_from INT, _to INT)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
SET enable_bitmapscan = OFF
AS $$
DECLARE
  __block_op_rows INT;
  __day_rows      INT;
  __month_rows    INT;
BEGIN
  /*
   * ===================================================================================
   * CTE: per_block
   * ===================================================================================
   * WHY MATERIALIZED: feeds all three downstream sinks; we want one scan, not three.
   *
   * Aggregates the operations_view range to one row per (block_num, op_type_id) and
   * attaches the block's day/month period for the rollups.
   */
  WITH per_block AS MATERIALIZED (
    SELECT
      ov.block_num,
      ov.op_type_id,
      COUNT(*)                              AS op_count,
      date_trunc('day',   bv.created_at)    AS by_day,
      date_trunc('month', bv.created_at)    AS by_month
    FROM hafbe_app.operations_view ov
    JOIN hafbe_app.blocks_view bv ON bv.num = ov.block_num
    WHERE ov.block_num BETWEEN _from AND _to
      AND ov.id >= hafd.operation_id(_from, 0)
      AND ov.id <  hafd.operation_id(_to + 1, 0)
    GROUP BY ov.block_num, ov.op_type_id, bv.created_at
  ),

  /*
   * SINK 1: block_operations -- one row per (block, op_type). Append-only.
   */
  ins_block_ops AS (
    INSERT INTO hafbe_app.block_operations (block_num, op_type_id, op_count)
    SELECT block_num, op_type_id, op_count
    FROM per_block
    ORDER BY block_num, op_type_id
    RETURNING 1
  ),

  /*
   * Daily roll-up of per_block. SUM across blocks within the same day.
   */
  agg_day AS (
    SELECT
      by_day                AS updated_at,
      op_type_id,
      SUM(op_count)::BIGINT AS op_count,
      MAX(block_num)::INT   AS last_block_num
    FROM per_block
    GROUP BY by_day, op_type_id
  ),

  /*
   * SINK 2: operation_type_stats_by_day -- additive upsert across batches.
   */
  ups_day AS (
    INSERT INTO hafbe_app.operation_type_stats_by_day AS a
      (updated_at, op_type_id, op_count, last_block_num)
    SELECT updated_at, op_type_id, op_count, last_block_num FROM agg_day
    ON CONFLICT ON CONSTRAINT pk_operation_type_stats_by_day DO UPDATE SET
      op_count       = a.op_count + EXCLUDED.op_count,
      last_block_num = GREATEST(a.last_block_num, EXCLUDED.last_block_num)
    RETURNING 1
  ),

  /*
   * Monthly roll-up of per_block.
   */
  agg_month AS (
    SELECT
      by_month              AS updated_at,
      op_type_id,
      SUM(op_count)::BIGINT AS op_count,
      MAX(block_num)::INT   AS last_block_num
    FROM per_block
    GROUP BY by_month, op_type_id
  ),

  /*
   * SINK 3: operation_type_stats_by_month -- additive upsert across batches.
   */
  ups_month AS (
    INSERT INTO hafbe_app.operation_type_stats_by_month AS a
      (updated_at, op_type_id, op_count, last_block_num)
    SELECT updated_at, op_type_id, op_count, last_block_num FROM agg_month
    ON CONFLICT ON CONSTRAINT pk_operation_type_stats_by_month DO UPDATE SET
      op_count       = a.op_count + EXCLUDED.op_count,
      last_block_num = GREATEST(a.last_block_num, EXCLUDED.last_block_num)
    RETURNING 1
  )

  SELECT
    (SELECT count(*) FROM ins_block_ops),
    (SELECT count(*) FROM ups_day),
    (SELECT count(*) FROM ups_month)
  INTO __block_op_rows, __day_rows, __month_rows;
END $$;

RESET ROLE;
