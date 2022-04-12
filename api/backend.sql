DROP SCHEMA IF EXISTS hafbe_backend CASCADE;

CREATE SCHEMA IF NOT EXISTS hafbe_backend;

CREATE EXTENSION IF NOT EXISTS plpython3u SCHEMA pg_catalog;

CREATE PROCEDURE hafbe_backend.create_api_user()
LANGUAGE 'plpgsql'
AS $$
BEGIN
  --recreate role for reading data
  IF (SELECT 1 FROM pg_roles WHERE rolname='hafbe_user') IS NOT NULL THEN
  DROP OWNED BY hafbe_user CASCADE;
  END IF;
  DROP ROLE IF EXISTS hafbe_user;
  CREATE ROLE hafbe_user;

  GRANT USAGE ON SCHEMA hafbe_backend TO hafbe_user;
  GRANT SELECT ON ALL TABLES IN SCHEMA hafbe_backend TO hafbe_user;

  GRANT USAGE ON SCHEMA hafbe_endpoints TO hafbe_user;
  GRANT SELECT ON ALL TABLES IN SCHEMA hafbe_endpoints TO hafbe_user;

  GRANT USAGE ON SCHEMA btracker_app TO hafbe_user;
  GRANT SELECT ON ALL TABLES IN SCHEMA btracker_app TO hafbe_user;
  GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA btracker_app TO hafbe_user;

  GRANT USAGE ON SCHEMA hafah_python TO hafbe_user;
  GRANT SELECT ON ALL TABLES IN SCHEMA hafah_python TO hafbe_user;
  GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA hafah_python TO hafbe_user;

  GRANT USAGE ON SCHEMA hive TO hafbe_user;
  GRANT SELECT ON ALL TABLES IN SCHEMA hive TO hafbe_user;
  GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA hive TO hafbe_user;
  
  -- add ability for admin to switch to hafbe_user role
  GRANT hafbe_user TO haf_admin;

  -- add hafbe schemas owner
  IF (SELECT 1 FROM pg_roles WHERE rolname='hafbe_owner') IS NOT NULL THEN
  DROP OWNED BY hafbe_owner CASCADE;
  END IF;
  DROP ROLE IF EXISTS hafbe_owner;
  CREATE ROLE hafbe_owner;
  
  ALTER SCHEMA hafbe_backend OWNER TO hafbe_owner;
  ALTER SCHEMA hafbe_endpoints OWNER TO hafbe_owner;
END
$$
;

CREATE FUNCTION hafbe_backend.get_block_num(_block_hash BYTEA)
RETURNS INT
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN num FROM hive.blocks WHERE hash=_block_hash;
END
$$
;

CREATE FUNCTION hafbe_backend.get_head_block_num()
RETURNS INT
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN num FROM hive.blocks_view ORDER BY num DESC LIMIT 1;
END
$$
;

CREATE FUNCTION hafbe_backend.get_block(_block_num INT)
RETURNS JSON
LANGUAGE 'plpython3u'
AS
$$
  global _block_num

  import subprocess
  import json

  return json.dumps(
    json.loads(
      subprocess.check_output([
      """
      curl -X POST https://api.hive.blog \
        -H 'Content-Type: application/json' \
        -d '{"jsonrpc": "2.0", "method": "block_api.get_block", "params": {"block_num": %d}, "id": null}'
      """ %_block_num
      ], shell=True).decode('utf-8')
    )['result']
  )
$$
;

CREATE FUNCTION hafbe_backend.get_witnesses_by_vote()
RETURNS JSON
LANGUAGE 'plpython3u'
AS 
$$
  import subprocess
  import json

  return json.dumps(
    json.loads(
      subprocess.check_output([
        
      """
      curl -X POST https://api.hive.blog \
        -H 'Content-Type: application/json' \
        -d '{"jsonrpc": "2.0", "method": "condenser_api.get_witnesses_by_vote", "params": [null,21], "id": null}'
      """ 
      ], shell=True).decode('utf-8')
    )['result']
  )
  $$
  ;