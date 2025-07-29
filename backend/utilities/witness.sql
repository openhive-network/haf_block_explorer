SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_backend.get_witness_id(_account_name TEXT)
RETURNS INT STABLE
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  _witness_id INT := (SELECT av.id FROM hive.accounts_view av WHERE av.name = _account_name);
BEGIN
  PERFORM hafbe_exceptions.validate_witness(_witness_id, _account_name);

  RETURN _witness_id;
END
$$;

RESET ROLE;
