SET ROLE hafbe_owner;

-- Transaction page endpoint
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_transaction(_trx_hash TEXT)
RETURNS hafbe_types.get_transaction -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
RETURN (
  SELECT ROW (
  transaction_json::JSON,
  hbv.created_at,
  NOW() - hbv.created_at)
  
-- _trx_hash TEXT -> BYTEA, __include_reversible = TRUE, __is_legacy_style = FALSE
FROM hafah_python.get_transaction_json(('\x' || _trx_hash)::BYTEA, TRUE, FALSE) AS transaction_json
JOIN hive.blocks_view hbv ON hbv.num = (transaction_json->>'block_num')::INT
);

END
$$;

RESET ROLE;
