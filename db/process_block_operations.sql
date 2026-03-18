SET ROLE hafbe_owner;

/*
 * process_block_operations: Aggregates operation counts per block and type.
 *
 * Core operations: Counts all operations grouped by block number and operation
 * type. Updates hafbe_app.block_operations table for fast lookup in blocksearch.
 */
CREATE OR REPLACE FUNCTION hafbe_app.process_block_operations(_from INT, _to INT)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
SET enable_bitmapscan = OFF
AS $$
BEGIN
  /*
   * ===================================================================================
   * CTE: operations
   * ===================================================================================
   * PURPOSE: Aggregate operation counts from the block range.
   *
   * DATA FLOW:
   *   1. Scans hafbe_app.operations_view for blocks in range
   *   2. Groups by (block_num, op_type_id)
   *   3. Counts occurrences per group
   *
   * OUTPUT: One row per (block_num, op_type_id) combination with count.
   */
  WITH operations AS (
    SELECT
      block_num,
      op_type_id,
      COUNT(*) AS op_count
    FROM hafbe_app.operations_view
    WHERE block_num BETWEEN _from AND _to
      AND id >= hafd.operation_id(_from, 0)
      AND id < hafd.operation_id(_to + 1, 0)
    GROUP BY block_num, op_type_id
    ORDER BY block_num, op_type_id
  )
  INSERT INTO hafbe_app.block_operations (block_num, op_type_id, op_count)
  SELECT block_num, op_type_id, op_count
  FROM operations;
END $$;

RESET ROLE;
