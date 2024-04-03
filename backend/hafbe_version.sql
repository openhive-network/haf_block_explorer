SET ROLE hafbe_owner;
  
CREATE OR REPLACE FUNCTION hafbe_backend.set_version(
    _git_hash TEXT
)
RETURNS void -- noqa: LT01, CP05
LANGUAGE 'plpgsql' VOLATILE 
AS
$$
DECLARE
_schema_hash TEXT := (SELECT schema_hash FROM hafbe_app.version LIMIT 1);
BEGIN
TRUNCATE TABLE hafbe_app.version;

IF _schema_hash IS NULL THEN
    INSERT INTO hafbe_app.version(schema_hash, runtime_hash) VALUES (_git_hash, _git_hash);
ELSE
    INSERT INTO hafbe_app.version(schema_hash, runtime_hash) VALUES (_schema_hash, _git_hash);
END IF;

END
$$;

RESET ROLE;
