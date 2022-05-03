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

  GRANT USAGE ON SCHEMA hafbe_exceptions TO hafbe_user;
  GRANT SELECT ON ALL TABLES IN SCHEMA hafbe_exceptions TO hafbe_user;

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

CREATE FUNCTION hafbe_backend.get_account_id(_account VARCHAR)
RETURNS INT
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN id FROM hive.accounts_view WHERE name = _account;
END
$$
;

CREATE FUNCTION hafbe_backend.format_op_types(_operation_id INT, _operation_name TEXT, _is_virtual BOOLEAN)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN ('[' || _operation_id || ', "' || split_part(_operation_name, '::', 3) || '", ' || _is_virtual || ']')::JSON;
END
$$
;

CREATE FUNCTION hafbe_backend.get_operation_types()
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN to_json(arr) FROM (
    SELECT ARRAY(
      SELECT
        hafbe_backend.format_op_types(id, name, is_virtual)
      FROM
        hive.operation_types
      ORDER BY id ASC
    ) arr
  ) result;
END
$$
;

CREATE FUNCTION hafbe_backend.get_acc_op_types(_account_id INT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN to_json(arr) FROM (
    SELECT ARRAY (
      SELECT
        hafbe_backend.format_op_types(operation_id, operation_name, is_virtual)
      FROM (
        SELECT DISTINCT
          haov.op_type_id AS "operation_id",
          hot.name AS "operation_name",
          hot.is_virtual AS "is_virtual"
        FROM
          hive.account_operations_view haov
        JOIN
          hive.operation_types hot ON hot.id = haov.op_type_id
        WHERE
          account_id = _account_id
        ORDER BY haov.op_type_id ASC
      ) acc_ops
    ) arr
  ) result;
END
$$
;

CREATE FUNCTION hafbe_backend.get_block_op_types(_block_num INT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN to_json(arr) FROM (
    SELECT ARRAY (
      SELECT
        hafbe_backend.format_op_types(operation_id, operation_name, is_virtual)
      FROM (
        SELECT DISTINCT
          hov.op_type_id AS "operation_id",
          hot.name AS "operation_name",
          hot.is_virtual AS "is_virtual"
        FROM
          hive.operations_view hov
        JOIN
          hive.operation_types hot ON hot.id = hov.op_type_id
        WHERE
          block_num = _block_num
        ORDER BY hov.op_type_id ASC
      ) acc_ops
    ) arr
  ) result;
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_backend.get_trx_hash(_block_num INT, _trx_in_block INT)
RETURNS TEXT
LANGUAGE 'plpgsql'
AS 
$$
BEGIN
  RETURN encode(trx_hash, 'escape')
  FROM hive.transactions_view htv
  WHERE htv.block_num = _block_num AND htv.trx_in_block = _trx_in_block;
END
$$
;

CREATE TYPE hafbe_backend.operations AS (
  trx_id TEXT,
  block INT,
  trx_in_block INT,
  op_in_trx INT,
  virtual_op BOOLEAN,
  timestamp TEXT,
  op JSON,
  operation_id BIGINT
);

CREATE OR REPLACE FUNCTION hafbe_backend.get_set_of_ops_by_account(_account_id INT, _start BIGINT, _limit BIGINT, _filter SMALLINT[], _head_block BIGINT)
RETURNS SETOF hafbe_backend.operations 
AS
$function$
BEGIN
  RETURN QUERY SELECT
    hafbe_backend.get_trx_hash(hov.block_num, hov.trx_in_block)::TEXT,
    hov.block_num::INT,
    hov.trx_in_block::INT,
    hov.op_pos::INT,
    hot.is_virtual::BOOLEAN,
    btrim(to_json(hov.timestamp)::TEXT, '"'::TEXT)::TEXT,
    hov.body::JSON,
    hov.id::BIGINT
  FROM hive.account_operations_view haov
  JOIN hive.operations_view hov ON hov.id = haov.operation_id
  JOIN hive.operation_types hot ON hot.id = haov.op_type_id
  WHERE haov.account_id = _account_id AND haov.account_op_seq_no <= _start AND haov.block_num <= _head_block AND (
    (SELECT array_length(_filter, 1)) IS NULL OR
    haov.op_type_id=ANY(_filter)
  )
  ORDER BY haov.account_op_seq_no DESC
  LIMIT _limit;
END
$function$
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
;

CREATE OR REPLACE FUNCTION hafbe_backend.get_ops_by_account(_account_id INT, _start BIGINT, _limit BIGINT, _filter SMALLINT[], _head_block BIGINT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN to_json(arr) FROM (
    SELECT ARRAY(
      SELECT to_json(hafbe_backend.get_set_of_ops_by_account(_account_id, _start, _limit, _filter, _head_block))
    ) arr
  ) result;
END
$$
;

CREATE FUNCTION hafbe_backend.get_block(_block_num INT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __block_api_data JSON = (hafbe_backend.get_block_api_data(_block_num));
BEGIN
  RETURN json_build_object(
    'block_num', _block_num,
    'block_hash', __block_api_data->>'block_id',
    'timestamp', __block_api_data->>'timestamp',
    'witness', __block_api_data->>'witness',
    'signing_key', __block_api_data->>'signing_key'
  );
END
$$
;

CREATE FUNCTION hafbe_backend.get_block_api_data(_block_num INT)
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
          -d '{"jsonrpc": "2.0", "method": "block_api.get_block", "params": {"block_num": %d}, "id": null}'
        """ % _block_num
      ], shell=True).decode('utf-8')
    )['result']['block']
  )
$$
;

CREATE OR REPLACE FUNCTION hafbe_backend.get_set_of_ops_by_block(_block_num INT, _start BIGINT, _limit BIGINT, _filter SMALLINT[])
RETURNS SETOF hafbe_backend.operations 
AS
$function$
BEGIN
  RETURN QUERY SELECT
    hafbe_backend.get_trx_hash(_block_num, hov.trx_in_block)::TEXT,
    hov.block_num::INT,
    hov.trx_in_block::INT,
    hov.op_pos::INT,
    hot.is_virtual::BOOLEAN,
    btrim(to_json(hov.timestamp)::TEXT, '"'::TEXT)::TEXT,
    hov.body::JSON,
    hov.id::BIGINT
  FROM hive.operations_view hov
  JOIN hive.operation_types hot ON hot.id = hov.op_type_id
  WHERE hov.block_num = _block_num AND hov.id <= _start AND (
    (SELECT array_length(_filter, 1)) IS NULL OR
    hov.op_type_id=ANY(_filter)
  )
  ORDER BY hov.id DESC
  LIMIT _limit;
END
$function$
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
;

CREATE OR REPLACE FUNCTION hafbe_backend.get_ops_by_block(_block_num INT, _start BIGINT, _limit BIGINT, _filter SMALLINT[])
RETURNS JSON
LANGUAGE 'plpgsql'
AS 
$$
BEGIN
  RETURN to_json(arr) FROM (
    SELECT ARRAY(
      SELECT to_json(hafbe_backend.get_set_of_ops_by_block(_block_num, _start, _limit, _filter))
    ) arr
  ) result;
END
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