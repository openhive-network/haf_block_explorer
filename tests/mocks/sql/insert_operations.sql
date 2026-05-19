-- =============================================================================
-- Insert mock operations into hafd.operations.
--
-- The fixture body has the wrapping form `{"type": "...", "value": {...}}`,
-- but body_value (what hafbe_app.operations_view exposes) is just the inner
-- value object. We strip the wrapper here to match HAF's storage shape.
-- =============================================================================

SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_backend.insert_mock_operations(IN _block_json JSON)
RETURNS VOID
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
  INSERT INTO hafd.operations(id, trx_in_block, op_pos, op_type_id, body_value)
  SELECT
    hafd.operation_id(block_num, op_pos),
    trx_in_block,
    op_pos,
    (SELECT ot.id FROM hafd.operation_types ot WHERE ot.name = op_name),
    (body::JSONB)->'value'
  FROM json_populate_recordset(
    NULL::hafbe_backend.mock_operation_type,
    _block_json->'operations'
  )
  -- Idempotent: re-running the installer should be a no-op for already-loaded ops.
  ON CONFLICT (id) DO NOTHING;
END
$$;

RESET ROLE;
