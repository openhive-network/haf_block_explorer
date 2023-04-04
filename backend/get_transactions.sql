CREATE FUNCTION hafbe_backend.get_transaction(_trx_hash TEXT)
RETURNS JSONB
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN
    transaction_json::JSONB || jsonb_build_object(
      'timestamp', hbv.created_at,
      'age', NOW() - hbv.created_at
    )
  -- _trx_hash TEXT -> BYTEA, __include_reversible = TRUE, __is_legacy_style = FALSE
  FROM hafah_python.get_transaction_json(('\x' || _trx_hash)::BYTEA, TRUE, FALSE) AS transaction_json
  JOIN hive.blocks_view hbv ON hbv.num = (transaction_json->>'block_num')::INT
  ;
END
$$
;
