SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_app.process_block_operations(_from INT, _to INT)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
SET enable_bitmapscan = OFF
AS
$$
BEGIN
  WITH operations AS (
    SELECT block_num, op_type_id, COUNT(*) AS count
    FROM hafbe_app.operations_view
    WHERE block_num BETWEEN _from AND _to
    GROUP BY block_num, op_type_id
    ORDER BY block_num, op_type_id
  )
  INSERT INTO hafbe_app.block_operations
    (block_num, op_type_id, op_count)
  SELECT
    block_num,
    op_type_id,
    count
  FROM operations;
END
$$;

RESET ROLE;
