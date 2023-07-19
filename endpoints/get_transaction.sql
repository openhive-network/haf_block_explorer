CREATE OR REPLACE FUNCTION hafbe_endpoints.get_transaction(_trx_hash TEXT)
RETURNS JSON
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN hafbe_backend.get_transaction(_trx_hash);
END
$$
;
