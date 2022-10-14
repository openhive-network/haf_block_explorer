DROP SCHEMA IF EXISTS hafbe_backend CASCADE;

CREATE SCHEMA IF NOT EXISTS hafbe_backend;

CREATE EXTENSION IF NOT EXISTS plpython3u SCHEMA pg_catalog;

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

CREATE FUNCTION hafbe_backend.find_matching_accounts(_partial_account_name TEXT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN btracker_app.find_matching_accounts(_partial_account_name);
END
$$
;

CREATE FUNCTION hafbe_backend.get_account_id(_account TEXT)
RETURNS INT
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN id FROM hive.accounts_view WHERE name = _account;
END
$$
;

CREATE FUNCTION hafbe_backend.format_op_types(_operation_id BIGINT, _operation_name TEXT, _is_virtual BOOLEAN)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN ('[' || _operation_id || ', "' || split_part(_operation_name, '::', 3) || '", ' || _is_virtual || ']')::JSON;
END
$$
;

CREATE TYPE hafbe_backend.op_types AS (
  operation_id BIGINT,
  operation_name TEXT,
  is_virtual BOOLEAN
);

CREATE FUNCTION hafbe_backend.get_set_of_op_types()
RETURNS SETOF hafbe_backend.op_types
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN QUERY SELECT
    id::BIGINT,
    name::TEXT,
    is_virtual::BOOLEAN
  FROM hive.operation_types
  ORDER BY id ASC;
END
$$
;

CREATE FUNCTION hafbe_backend.get_op_types()
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN json_agg(hafbe_backend.format_op_types(operation_id, operation_name, is_virtual))
  FROM hafbe_backend.get_set_of_op_types();
END
$$
;

CREATE FUNCTION hafbe_backend.get_set_of_acc_op_types(_account_id INT)
RETURNS SETOF hafbe_backend.op_types
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN QUERY SELECT
    haov.op_type_id::BIGINT,
    hot.name::TEXT,
    hot.is_virtual::BOOLEAN
  FROM (
    SELECT DISTINCT op_type_id
    FROM hive.account_operations_view
    WHERE account_id = _account_id
  ) haov

  JOIN LATERAL (
    SELECT id, name, is_virtual
    FROM hive.operation_types
  ) hot ON hot.id = haov.op_type_id
  ORDER BY haov.op_type_id ASC;
END
$$
;

CREATE FUNCTION hafbe_backend.get_acc_op_types(_account_id INT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN json_agg(hafbe_backend.format_op_types(operation_id, operation_name, is_virtual))
  FROM hafbe_backend.get_set_of_acc_op_types(_account_id);
END
$$
;

CREATE FUNCTION hafbe_backend.get_set_of_block_op_types(_block_num INT)
RETURNS SETOF hafbe_backend.op_types
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN QUERY SELECT
    hov.op_type_id::BIGINT,
    hot.name::TEXT,
    hot.is_virtual::BOOLEAN
  FROM (
    SELECT DISTINCT op_type_id
    FROM hive.operations_view
    WHERE block_num = _block_num
  ) hov

  JOIN LATERAL (
    SELECT id, name, is_virtual
    FROM hive.operation_types
  ) hot ON hot.id = hov.op_type_id
  ORDER BY hov.op_type_id ASC;
END
$$
;

CREATE FUNCTION hafbe_backend.get_block_op_types(_block_num INT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN json_agg(hafbe_backend.format_op_types(operation_id, operation_name, is_virtual))
  FROM hafbe_backend.get_set_of_block_op_types(_block_num);
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_backend.get_trx_hash(_block_num INT, _trx_in_block INT)
RETURNS TEXT
LANGUAGE 'plpgsql'
AS 
$$
BEGIN
  RETURN encode(trx_hash, 'hex')
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
  operations JSON,
  operation_id BIGINT,
  acc_operation_id BIGINT
);

CREATE FUNCTION hafbe_backend.get_set_of_ops_by_account(_account_id INT, _top_op_id BIGINT, _limit BIGINT, _filter SMALLINT[], _date_start TIMESTAMP, _date_end TIMESTAMP)
RETURNS SETOF hafbe_backend.operations 
AS
$function$
DECLARE
  __filter_ops BOOLEAN = ((SELECT array_length(_filter, 1)) IS NULL);
  __no_start_date BOOLEAN = (_date_start IS NULL);
  __no_end_date BOOLEAN = (_date_end IS NULL);
BEGIN
  RETURN QUERY SELECT
    encode(htv.trx_hash, 'hex')::TEXT,
    haov_hov.block_num::INT,
    haov_hov.trx_in_block::INT,
    haov_hov.op_pos::INT,
    hot.is_virtual::BOOLEAN,
    haov_hov.timestamp::TEXT,
    haov_hov.body::JSON,
    haov_hov.operation_id::BIGINT,
    haov_hov.account_op_seq_no::BIGINT
  FROM (
    SELECT *
    FROM hive.account_operations_view haov
    JOIN (
      SELECT id, trx_in_block, op_pos, timestamp, body
      FROM hive.operations_view
    ) hov ON hov.id = haov.operation_id
    WHERE
      haov.account_id = _account_id AND
      haov.account_op_seq_no <= _top_op_id AND (
      __filter_ops OR haov.op_type_id=ANY(_filter)) AND
      (__no_start_date OR hov.timestamp >= _date_start) AND
      (__no_end_date OR hov.timestamp < _date_end)
  ) haov_hov
  JOIN (
    SELECT is_virtual, id
    FROM hive.operation_types
  ) hot ON hot.id = haov_hov.op_type_id
  JOIN (
    SELECT trx_hash, block_num, trx_in_block
    FROM hive.transactions_view
  ) htv ON htv.block_num = haov_hov.block_num AND htv.trx_in_block = haov_hov.trx_in_block
  ORDER BY haov_hov.operation_id DESC
  LIMIT _limit;
END
$function$
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
;

CREATE OR REPLACE FUNCTION hafbe_backend.get_ops_by_account(_account_id INT, _top_op_id BIGINT, _limit BIGINT, _filter SMALLINT[], _date_start TIMESTAMP, _date_end TIMESTAMP)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN CASE WHEN arr IS NOT NULL THEN to_json(arr) ELSE '[]'::JSON END FROM (
    SELECT ARRAY(
      SELECT to_json(hafbe_backend.get_set_of_ops_by_account(_account_id, _top_op_id, _limit, _filter, _date_start, _date_end))
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
  __block_api_data JSON = (((SELECT hafbe_backend.get_block_api_data(_block_num))->'result')->'block');
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
    )
  )
$$
;

CREATE OR REPLACE FUNCTION hafbe_backend.get_set_of_ops_by_block(_block_num INT, _top_op_id BIGINT, _limit BIGINT, _filter SMALLINT[])
RETURNS SETOF hafbe_backend.operations 
AS
$function$
DECLARE
  __filter_ops BOOLEAN = ((SELECT array_length(_filter, 1)) IS NULL);
BEGIN
  RETURN QUERY SELECT
    hafbe_backend.get_trx_hash(_block_num, hov.trx_in_block)::TEXT,
    _block_num::INT,
    hov.trx_in_block::INT,
    hov.op_pos::INT,
    hot.is_virtual::BOOLEAN,
    hov.timestamp::TEXT,
    hov.body::JSON,
    hov.id::BIGINT,
    NULL::BIGINT
  FROM (
    SELECT block_num, op_type_id, trx_in_block, op_pos, timestamp, body, id
    FROM hive.operations_view
  ) hov
  JOIN LATERAL (
    SELECT id, is_virtual
    FROM hive.operation_types
  ) hot ON hot.id = hov.op_type_id
  WHERE hov.block_num = _block_num AND hov.id <= _top_op_id AND (
    __filter_ops OR hov.op_type_id=ANY(_filter)
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

CREATE OR REPLACE FUNCTION hafbe_backend.get_ops_by_block(_block_num INT, _top_op_id BIGINT, _limit BIGINT, _filter SMALLINT[])
RETURNS JSON
LANGUAGE 'plpgsql'
AS 
$$
BEGIN
  RETURN CASE WHEN arr IS NOT NULL THEN to_json(arr) ELSE '[]'::JSON END FROM (
    SELECT ARRAY(
      SELECT to_json(hafbe_backend.get_set_of_ops_by_block(_block_num, _top_op_id, _limit, _filter))
    ) arr
  ) result;
END
$$
;

CREATE TYPE hafbe_backend.witness_voters AS (
  voter_id INT,
  vests NUMERIC,
  account_vests BIGINT,
  proxied_vests NUMERIC
);

CREATE FUNCTION hafbe_backend.get_set_of_witness_voters(_witness_id INT, _limit INT)
RETURNS SETOF hafbe_backend.witness_voters
AS
$function$
BEGIN
  RETURN QUERY SELECT
    v_voter_id,
    vests_sum,
    cab_account_vests,
    f_proxied_vests
  FROM (
    SELECT
      v_voter_id,
      cab_account_vests + f_proxied_vests AS vests_sum,
      cab_account_vests,
      f_proxied_vests
    FROM (
      SELECT
        v_voter_id,
        CASE WHEN is_proxied IS TRUE THEN 0 ELSE cab_account_vests END AS cab_account_vests,
        f_proxied_vests
      FROM (
        SELECT
          voters.voter_id AS v_voter_id,
          cab.balance AS cab_account_vests,
          hafbe_backend.get_proxied_vests(voters.voter_id) AS f_proxied_vests,
          hafbe_backend.is_voter_proxied(voters.voter_id) AS is_proxied
        FROM (
          SELECT DISTINCT ON (voter_id)
            voter_id, approve
          FROM (
            SELECT voter_id, approve
            FROM hafbe_app.witness_votes
            WHERE witness_id = _witness_id
            ORDER BY operation_id
          ) votes_ordered
        ) voters
        JOIN LATERAL (
          SELECT name, id
          FROM hive.accounts_view
        ) acc ON acc.id = voters.voter_id
        JOIN LATERAL (
          SELECT balance, account, nai
          FROM btracker_app.current_account_balances
        ) cab ON cab.account = acc.name
        WHERE voters.approve IS TRUE AND cab.nai = 37
      ) vests
    ) is_proxied
  ) vests_sum
  ORDER BY vests_sum DESC
  LIMIT _limit;
END
$function$
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
;

CREATE OR REPLACE FUNCTION hafbe_backend.get_witness_voters(_witness_id INT, _limit INT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS 
$$
BEGIN
  RETURN CASE WHEN arr IS NOT NULL THEN to_json(arr) ELSE '[]'::JSON END FROM (
    SELECT ARRAY(
      SELECT to_json(hafbe_backend.get_set_of_witness_voters(_witness_id, _limit))
    ) arr
  ) result;
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_backend.was_acc_unproxied(_account_id INT, _proxy_id INT, _operation_id BIGINT)
RETURNS TABLE (
  one INT
)
LANGUAGE 'plpgsql'
AS 
$$
BEGIN
  RETURN QUERY SELECT 1
  FROM hafbe_app.account_proxies
  WHERE account_id = _account_id AND proxy_id = _proxy_id AND proxy IS FALSE AND operation_id > _operation_id;
END
$$
;

CREATE FUNCTION hafbe_backend.get_proxied_vests(_voter_id INT)
RETURNS TABLE (
  _balance NUMERIC
)
AS
$function$
BEGIN
  RETURN QUERY SELECT CASE WHEN balance IS NULL THEN 0 ELSE balance END
  FROM (
    SELECT SUM(cab.balance) AS balance
    FROM (
      SELECT
        CASE WHEN balance < 0 THEN 0 ELSE balance END,
        account,
        nai
      FROM btracker_app.current_account_balances
    ) cab
    JOIN LATERAL (
      SELECT name, id
      FROM hive.accounts_view
    ) hav ON hav.name = cab.account
    JOIN LATERAL (
      SELECT DISTINCT ON (account_id)
        account_id, proxy_id, operation_id
      FROM (
        SELECT account_id, proxy_id, operation_id
        FROM hafbe_app.account_proxies
        WHERE proxy_id = _voter_id AND proxy IS TRUE
        ORDER BY operation_id DESC
      ) proxy_ops
    ) ap ON ap.account_id = hav.id
    WHERE (SELECT hafbe_backend.was_acc_unproxied(ap.account_id, ap.proxy_id, ap.operation_id)) IS NULL AND cab.nai = 37
  ) is_null;
END
$function$
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
;

CREATE FUNCTION hafbe_backend.is_voter_proxied(_voter_id INT)
RETURNS TABLE (
  proxied BOOLEAN
)
AS
$function$
BEGIN
  RETURN QUERY SELECT CASE WHEN (
    SELECT proxy_id
    FROM (
      SELECT account_id, proxy_id, operation_id
      FROM hafbe_app.account_proxies
      WHERE account_id = _voter_id AND proxy IS TRUE
      ORDER BY operation_id DESC
      LIMIT 1
    ) ap
    WHERE (SELECT hafbe_backend.was_acc_unproxied(ap.account_id, ap.proxy_id, ap.operation_id)) IS NULL
  )
  IS NOT NULL THEN TRUE ELSE FALSE END;
END
$function$
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
;

CREATE FUNCTION hafbe_backend.get_account(_account TEXT)
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
          -d '{"jsonrpc": "2.0", "method": "condenser_api.get_accounts", "params": [["%s"]], "id": null}'
        """ % _account
      ], shell=True).decode('utf-8')
    )['result'][0]
  )
$$
;

CREATE FUNCTION hafbe_backend.parse_profile_picture(_account_data JSON, _key TEXT)
RETURNS TEXT
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __profile_image TEXT;
BEGIN
  BEGIN
    SELECT INTO __profile_image ( (
      ((_account_data->>_key)::JSON)->>'profile'
      )::JSON )->>'profile_image';
  EXCEPTION WHEN invalid_text_representation THEN
    SELECT NULL INTO __profile_image;
  END;
  RETURN __profile_image;
END
$$
;