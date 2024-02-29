SET ROLE hafbe_owner;

-- Transaction page endpoint
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_transaction(_trx_hash TEXT)
RETURNS hafbe_types.get_transaction -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
RETURN (
  
  WITH select_transaction AS MATERIALIZED 
  (
  SELECT transaction_json::JSON,
  bv.created_at,
  NOW() - bv.created_at
	-- _trx_hash TEXT -> BYTEA, __include_reversible = TRUE, __is_legacy_style = FALSE
  FROM hafah_python.get_transaction_json(('\x' || _trx_hash)::BYTEA, TRUE, FALSE) AS transaction_json
  JOIN hive.blocks_view bv ON bv.num = (transaction_json->>'block_num')::INT
  )
  SELECT ROW (
	  json_build_object(
	  'ref_block_num', transaction_json->>'ref_block_num',
	  'ref_block_prefix', transaction_json->>'ref_block_prefix',
	  'extensions', transaction_json->>'extensions',
	  'expiration', transaction_json->>'expiration',
	  'operations', (transaction_json->>'operations')::JSON,
	  'signatures', transaction_json->>'signatures'
	  ),
	  transaction_json->>'transaction_id',
	  (transaction_json->>'block_num')::INT,
	  (transaction_json->>'transaction_num')::INT,
	  created_at,
	  NOW() - created_at)
 FROM select_transaction
 
);

END
$$;


RESET ROLE;
