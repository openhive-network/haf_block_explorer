SET ROLE hafbe_owner;

/*
 * process_block_operations: Aggregates operation counts per block/type and rolls them
 * up to per-day and per-month per-op-type stats in the same scan.
 *
 * Three sinks, fed by a single MATERIALIZED CTE:
 *   1. hafbe_app.block_operations              -- one row per (block_num, op_type_id)
 *   2. hafbe_app.operation_type_stats_by_day   -- one row per (day,   op_type_id)
 *   3. hafbe_app.operation_type_stats_by_month -- one row per (month, op_type_id)
 *
 * Combining all three here avoids re-reading freshly-inserted block_operations rows
 * in a follow-up processor (which would seq-scan during MASSIVE sync, before the
 * block_operations indexes exist) and keeps a single pass over the source ops.
 *
 * Daily/monthly stats use additive upsert so counts accumulate across MASSIVE batches.
 */

/*
 * count_ops_in_range: (block_num, op_type_id, op_count) for a block range.
 *
 * During MASSIVE sync the integrated balance-tracker sub-app has already copied this
 * exact range of operations into the session temp table _btracker_ops_batch
 * (btracker_prefetch_operations runs earlier in the same
 * hafbe_app.log_and_process_blocks iteration and same backend). Aggregating that temp
 * table instead of re-scanning operations_view measured 3.3x faster (1004ms -> 302ms
 * per 10k-block batch at block ~57M).
 *
 * The temp table is btracker's private detail, so treat it strictly as a cache: use it
 * only if it exists AND all of its rows fall inside [_from, _to] (a leftover table from
 * an earlier range fails the min/max guard because block ranges only move forward).
 * Anything else -- LIVE single-block processing where no prefetch ran, a stale table,
 * standalone deployments -- falls back to the operations_view scan, which is the
 * previous behavior verbatim.
 */
CREATE OR REPLACE FUNCTION hafbe_app.count_ops_in_range(_from INT, _to INT)
RETURNS TABLE(block_num INT, op_type_id SMALLINT, op_count BIGINT)
LANGUAGE 'plpgsql' VOLATILE
ROWS 60000
SET jit = OFF
SET enable_bitmapscan = OFF
AS $$
DECLARE
  __min INT;
  __max INT;
BEGIN
  IF to_regclass('pg_temp._btracker_ops_batch') IS NOT NULL THEN
    SELECT min(b.block_num), max(b.block_num) INTO __min, __max FROM _btracker_ops_batch b;
    IF __min >= _from AND __max <= _to THEN
      RETURN QUERY
      SELECT b.block_num, b.op_type_id, COUNT(*) AS op_count
      FROM _btracker_ops_batch b
      GROUP BY b.block_num, b.op_type_id;
      RETURN;
    END IF;
  END IF;

  RETURN QUERY
  SELECT ov.block_num, ov.op_type_id, COUNT(*) AS op_count
  FROM hafbe_app.operations_view ov
  WHERE ov.block_num BETWEEN _from AND _to
    AND ov.id >= hafd.operation_id(_from, 0)
    AND ov.id <  hafd.operation_id(_to + 1, 0)
  GROUP BY ov.block_num, ov.op_type_id;
END $$;

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
   * count_ops_in_range delivers one pre-aggregated row per (block_num, op_type_id)
   * (from the btracker prefetch table when available, see above), so blocks_view is
   * joined against the ~60k aggregated rows rather than every operation row.
   */
  WITH per_block AS MATERIALIZED (
    SELECT
      s.block_num,
      s.op_type_id,
      s.op_count,
      date_trunc('day',   bv.created_at)    AS by_day,
      date_trunc('month', bv.created_at)    AS by_month
    FROM hafbe_app.count_ops_in_range(_from, _to) s
    -- The explicit range on bv.num is redundant with the join condition but
    -- necessary: the planner has no range statistics for the function scan's
    -- block_num output, and blocks_view is a reversible-union view - without the
    -- direct qual, blocks_view is hash-joined in full (~22s/block at 109M blocks;
    -- with it, an index range scan, <1ms).
    JOIN hafbe_app.blocks_view bv ON bv.num = s.block_num
                                 AND bv.num BETWEEN _from AND _to
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
