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

CREATE FUNCTION hafbe_backend.get_operation_types()
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN to_json(result) FROM (
    SELECT 
      array_agg(id) AS "operation_id",
      array_agg(split_part(name, '::', 3)) AS "operation_name",
      array_agg(is_virtual) AS "is_virtual"
    FROM hive.operation_types
    ) result;
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_backend.get_ops_by_account(_account VARCHAR, _start BIGINT, _limit BIGINT, _filter SMALLINT[], _head_block BIGINT)
RETURNS JSON
AS
$function$
BEGIN
  RETURN to_json(arr) FROM (
    SELECT ARRAY(
      SELECT to_json(ops_json) FROM (
        SELECT
          (CASE WHEN ops.trx_in_block < 0 THEN
            '0000000000000000000000000000000000000000'
          ELSE 
            encode((SELECT trx_hash FROM hive.transactions_view WHERE ops.trx_in_block >= 0 AND acc_ops.block_num = block_num AND ops.trx_in_block = trx_in_block), 'escape')
          END) AS "trx_id",
          acc_ops.block_num AS "block",
          (CASE WHEN ops.trx_in_block < 0 THEN 4294967295 ELSE ops.trx_in_block END) AS "trx_in_block",
          ops.op_pos::BIGINT AS "op_in_trx",
          op_types.is_virtual AS "virtual_op",
          btrim(to_json(ops."timestamp")::TEXT, '"'::TEXT) AS "timestamp",
          ops.body::JSON AS "op",
          acc_ops.account_op_seq_no AS "operation_id"
        FROM (
          SELECT
            operation_id,
            op_type_id,
            block_num,
            account_op_seq_no
          FROM
            hive.account_operations_view
          WHERE
            account_id = (SELECT id FROM hive.accounts WHERE name = _account) AND 
            account_op_seq_no <= _start AND 
            block_num <= _head_block AND (
              (SELECT array_length(_filter, 1)) IS NULL OR
              op_type_id=ANY(_filter)
            )
          ORDER BY account_op_seq_no DESC
          LIMIT _limit
        ) acc_ops

        JOIN LATERAL (
          SELECT
            body,
            op_pos,
            timestamp,
            trx_in_block
          FROM
            hive.operations_view
          WHERE acc_ops.operation_id = id
        ) ops ON TRUE

        JOIN LATERAL (
          SELECT
            is_virtual
          FROM
            hive.operation_types
          WHERE acc_ops.op_type_id = id
        ) op_types ON TRUE
      ) ops_json
    ) arr
  ) result;
END
$function$
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
;

CREATE FUNCTION hafbe_backend.get_block(_block_num INT,  _filter SMALLINT[])
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __block_api_data JSON = (hafbe_backend.get_block_witness_data(_block_num));
BEGIN
  RETURN json_build_object(
    'block_num', _block_num,
    'block_hash', (SELECT encode(hash, 'escape') FROM hive.blocks WHERE num=_block_num),
    'timestamp', (SELECT created_at FROM hive.blocks WHERE num=_block_num),
    'witness', (__block_api_data->>'witness'),
    'signing_key', (__block_api_data->>'signing_key'),
    'transaction_hashes', (__block_api_data->'transaction_ids'),
    'transactions', ( hafbe_backend.get_transactions(
      (SELECT ARRAY(
        SELECT json_array_elements_text(__block_api_data->'transaction_ids'))
      )::BYTEA[],
      _filter) )
  );
END
$$
;

CREATE FUNCTION hafbe_backend.get_block_witness_data(_block_num INT)
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

CREATE OR REPLACE FUNCTION hafbe_backend.get_transactions(_trx_hash_array BYTEA[], _filter SMALLINT[])
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN to_json(arr) FROM (
    SELECT ARRAY(
      SELECT to_json(json_data) FROM (
        SELECT
          encode(trxs.trx_hash, 'escape') AS "trx_hash",
          trxs.ref_block_num,
          trxs.ref_block_prefix,
          trxs.expiration,
          trxs.trx_in_block,
          (CASE WHEN multisig.signature_num = 0 THEN
            ARRAY[trxs.signature]
          ELSE
            array_prepend(
              trxs.signature, (SELECT ARRAY(
                SELECT encode(signature, 'escape') FROM hive.transactions_multisig_view WHERE trx_hash=trxs.trx_hash)
              )
            )
          END) AS "signatures",
          (SELECT hafbe_backend.get_ops_in_transaction(trxs.block_num, trxs.trx_in_block, _filter)) AS "operations"
        FROM (
          SELECT
            trx_hash,
            block_num,
            ref_block_num,
            ref_block_prefix,
            expiration,
            trx_in_block,
            encode(signature, 'escape') AS "signature"
          FROM
            hive.transactions_view
          WHERE
            trx_hash=ANY(_trx_hash_array)
        ) trxs

        JOIN LATERAL (
          SELECT
            COUNT(signature) AS "signature_num"
          FROM
            hive.transactions_multisig_view
          WHERE 
            trx_hash=ANY(_trx_hash_array)
        ) multisig ON TRUE
        
        ORDER BY trxs.trx_in_block DESC
      ) json_data
    ) arr
  ) result;
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_backend.get_ops_in_transaction(_block_num INT, _trx_in_block INT, _filter SMALLINT[])
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN to_json(arr) FROM (
    SELECT ARRAY(
      SELECT to_json(json_data) FROM (
        SELECT
          hov.body::JSON,
          hov.op_pos AS "op_in_trx",
          hot.is_virtual,
          hot.id AS "op_type_id"
        FROM
          hive.operations_view hov
        JOIN
          hive.operation_types hot ON hov.op_type_id = hot.id
        WHERE
          hov.block_num = _block_num AND
          hov.trx_in_block = _trx_in_block
        ORDER BY hov.op_pos DESC
      ) json_data
      WHERE
        (SELECT array_length(_filter, 1)) IS NULL OR op_type_id=ANY(_filter)
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