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
  RETURN ('[' || _operation_id || ', "' || split_part(_operation_name, '::', 3) || '", ' || _is_virtual || ']');
END
$$
;

CREATE TYPE hafbe_backend.op_types AS (
  op_type_id INT,
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
    id::INT,
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
  RETURN CASE WHEN res.arr IS NOT NULL THEN res.arr ELSE '[]'::JSON END FROM (
    SELECT json_agg(hafbe_backend.format_op_types(op_type_id, operation_name, is_virtual)) AS arr
    FROM hafbe_backend.get_set_of_op_types()
  ) res;
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
    aoc.op_type_id,
    hot.name::TEXT,
    hot.is_virtual::BOOLEAN
  FROM (
    SELECT op_type_id
    FROM hafbe_app.account_operation_cache
    WHERE account_id = _account_id
  ) aoc

  JOIN LATERAL (
    SELECT id, name, is_virtual
    FROM hive.operation_types
  ) hot ON hot.id = aoc.op_type_id
  ORDER BY aoc.op_type_id ASC;
END
$$
;

CREATE FUNCTION hafbe_backend.get_acc_op_types(_account_id INT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN CASE WHEN res.arr IS NOT NULL THEN res.arr ELSE '[]'::JSON END FROM (
    SELECT json_agg(hafbe_backend.format_op_types(op_type_id, operation_name, is_virtual)) AS arr
    FROM hafbe_backend.get_set_of_acc_op_types(_account_id)
  ) res;
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
    hot.id::INT,
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
  RETURN CASE WHEN res.arr IS NOT NULL THEN res.arr ELSE '[]'::JSON END FROM (
    SELECT json_agg(hafbe_backend.format_op_types(op_type_id, operation_name, is_virtual)) AS arr
    FROM hafbe_backend.get_set_of_block_op_types(_block_num)
  ) res;
END
$$
;

CREATE FUNCTION hafbe_backend.get_trx_hash(_block_num INT, _trx_in_block INT)
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

CREATE FUNCTION hafbe_backend.get_ops_by_account(_account_id INT, _top_op_id BIGINT, _limit BIGINT, _filter SMALLINT[], _date_start TIMESTAMP, _date_end TIMESTAMP)
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

CREATE FUNCTION hafbe_backend.get_set_of_ops_by_block(_block_num INT, _top_op_id BIGINT, _limit BIGINT, _filter SMALLINT[])
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

CREATE FUNCTION hafbe_backend.get_ops_by_block(_block_num INT, _top_op_id BIGINT, _limit BIGINT, _filter SMALLINT[])
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
  account TEXT,
  vests NUMERIC,
  account_vests BIGINT,
  proxied_vests NUMERIC,
  operation_id BIGINT
);

CREATE FUNCTION hafbe_backend.get_set_of_witness_voters(_witness_id INT)
RETURNS SETOF hafbe_backend.witness_voters
AS
$function$
BEGIN
  RETURN QUERY SELECT
    hav.name::TEXT AS account,
    CASE WHEN cab.balance IS NULL THEN 0 ELSE cab.balance END + proxied_vests AS vests,
    CASE WHEN cab.balance IS NULL THEN 0 ELSE cab.balance END AS account_vests,
    proxied_vests,
    operation_id
  FROM (
    SELECT
      voter_id, operation_id
    FROM (
      SELECT
        ROW_NUMBER() OVER (PARTITION BY voter_id ORDER BY operation_id DESC) AS row_n,
        voter_id, approve, operation_id
      FROM hafbe_app.witness_votes
      WHERE witness_id = _witness_id
    ) row_count
    WHERE row_n = 1 AND approve = TRUE
  ) wv

  JOIN LATERAL (
    SELECT proxied_vests
    FROM hafbe_backend.get_proxied_vests(voter_id)
  ) prox_vests ON TRUE

  JOIN LATERAL (
    SELECT proxied
    FROM hafbe_backend.is_voter_proxied(voter_id)
  ) is_prox ON TRUE

  JOIN (
    SELECT name, id
    FROM hive.accounts_view
  ) hav ON hav.id = voter_id

  LEFT JOIN (
    SELECT balance, account
    FROM btracker_app.current_account_balances
    WHERE nai = 37
  ) cab ON is_prox.proxied IS FALSE AND cab.account = hav.name;
END
$function$
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
;

CREATE TYPE hafbe_backend.witness_voters_history AS (
  account TEXT,
  vests NUMERIC,
  account_vests BIGINT,
  proxied_vests NUMERIC,
  timestamp TIMESTAMP
);

CREATE FUNCTION hafbe_backend.get_witness_voters_ordered(_witness_id INT, _limit INT, _order_by TEXT, _order_is TEXT)
RETURNS SETOF hafbe_backend.witness_voters_history
LANGUAGE 'plpgsql'
AS 
$$
BEGIN
  RETURN QUERY EXECUTE format(
    $query$
      SELECT account, vests, account_vests, proxied_vests, hov.timestamp
      FROM hafbe_backend.get_set_of_witness_voters(%L)
      
      JOIN LATERAL (
        SELECT timestamp
        FROM hive.operations_view
        WHERE id = operation_id
      ) hov ON TRUE
      ORDER BY
        (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
        (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC
      LIMIT %L;
    $query$, _witness_id, _order_is, _order_by, _order_is, _order_by, _limit
  ) res;
END
$$
;

CREATE FUNCTION hafbe_backend.get_witness_voters(_witness_id INT, _limit INT, _order_by TEXT, _order_is TEXT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS 
$$
BEGIN
  RETURN CASE WHEN arr IS NOT NULL THEN to_json(arr) ELSE '[]'::JSON END FROM (
    SELECT ARRAY(
      SELECT hafbe_backend.get_witness_voters_ordered(_witness_id, _limit, _order_by, _order_is)
    ) arr
  ) result;
END
$$
;

CREATE FUNCTION hafbe_backend.is_voter_proxied(_voter_id INT)
RETURNS TABLE (
  proxied BOOLEAN
)
AS
$function$
BEGIN
  RETURN QUERY SELECT proxy
  FROM (
    SELECT
      ROW_NUMBER() OVER (PARTITION BY account_id ORDER BY operation_id DESC) AS row_n,
      proxy
    FROM hafbe_app.account_proxies
    WHERE account_id = _voter_id
  ) row_count
  WHERE row_n = 1;
END
$function$
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
;

CREATE FUNCTION hafbe_backend.get_proxied_vests(_voter_id INT)
RETURNS TABLE (
  proxied_vests NUMERIC
)
AS
$function$
BEGIN
  RETURN QUERY SELECT (SUM(cab.balance))::NUMERIC
  FROM (
    SELECT
      ROW_NUMBER() OVER (PARTITION BY account_id ORDER BY operation_id DESC) AS row_n,
      account_id, proxy, operation_id
    FROM hafbe_app.account_proxies
    WHERE proxy_id = _voter_id
  ) row_count

  JOIN (
    SELECT name, id
    FROM hive.accounts_view
  ) hav ON hav.id = account_id

  JOIN (
    SELECT
      CASE WHEN balance < 0 THEN 0 ELSE balance END AS balance,
      account
    FROM btracker_app.current_account_balances cab
    WHERE nai = 37
  ) cab ON cab.account = hav.name

  WHERE row_n = 1 AND proxy = TRUE;
END
$function$
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
;

CREATE TYPE hafbe_backend.witnesses AS (
  witness TEXT,
  url TEXT,
  votes NUMERIC,
  votes_daily_change BIGINT,
  voters_num INT,
  voters_num_change INT,
  price_feed TEXT, --JSON,
  bias INT,
  feed_age INTERVAL,
  block_size INT,
  signing_key TEXT,
  version TEXT
);

CREATE FUNCTION hafbe_backend.get_set_of_witnesses(_limit INT)
RETURNS SETOF hafbe_backend.witnesses
AS
$function$
DECLARE
  __first_op_today BIGINT = (SELECT id FROM hive.operations_view WHERE timestamp >= 'today'::TIMESTAMP ORDER BY id LIMIT 1);
BEGIN
  RETURN QUERY SELECT
    witness::TEXT,
    url_data->>'url' AS url,
    votes,
    ((votes_change_data->>'votes')::NUMERIC - votes)::BIGINT AS votes_daily_change,
    voters_num,
    ((votes_change_data->>'voters_num')::INT - voters_num)::INT AS voters_num_change,
    feed_data->>'exchange_rate' AS price_feed,
    --(feed_data->'exchange_rate'->'quote'->>'amount')::INT - 1000 AS bias
    0 AS bias,
    (NOW() - (feed_data->>'timestamp')::TIMESTAMP)::INTERVAL AS feed_age,
    (block_size_data->>'block_size')::INT AS block_size,
    signing_data->>'signing_key' AS signing_key,
    '1.25.0' AS version
  FROM (
    SELECT
      witness,
      votes,
      voters_num,
      hafbe_backend.get_witness_votes_stats(witness_id, __first_op_today) AS votes_change_data,
      hafbe_backend.get_witness_url(witness_id) AS url_data,
      hafbe_backend.get_witness_exchange_rate(witness_id) AS feed_data,
      hafbe_backend.get_witness_block_size(witness_id) AS block_size_data,
      hafbe_backend.get_witness_signing_key(witness_id) AS signing_data
    FROM (
      SELECT
        witness_id,
        witness,
        (votes_data->>'votes')::NUMERIC AS votes,
        (votes_data->>'voters_num')::INT AS voters_num
      FROM (
        SELECT
          wv.witness_id AS witness_id,
          hav.name AS witness,
          hafbe_backend.get_witness_votes_stats(wv.witness_id) AS votes_data
        FROM (
          SELECT DISTINCT witness_id
          FROM hafbe_app.witness_votes
        ) wv

        JOIN (
          SELECT name, id
          FROM hive.accounts_view
        ) hav ON hav.id = wv.witness_id
      ) witness_votes
    ) votes_and_num
    ORDER BY votes DESC
    LIMIT _limit
  ) daily_change;
END
$function$
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
;

CREATE FUNCTION hafbe_backend.get_witnesses(_limit INT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS 
$$
BEGIN
  RETURN CASE WHEN arr IS NOT NULL THEN to_json(arr) ELSE '[]'::JSON END FROM (
    SELECT ARRAY(
      SELECT hafbe_backend.get_set_of_witnesses(_limit)
    ) arr
  ) result;
END
$$
;

CREATE FUNCTION hafbe_backend.get_witness_votes_stats(_witness_id INT, _first_op_today BIGINT = 9223372036854775807)
RETURNS TABLE (
  votes NUMERIC,
  voters_num INT
)
AS
$function$
BEGIN
  RETURN QUERY SELECT
    CASE WHEN votes IS NULL THEN 0 ELSE votes END,
    voters_num
  FROM (
    SELECT
      SUM(vests)::NUMERIC AS votes,
      COUNT(*)::INT AS voters_num
    FROM hafbe_backend.get_set_of_witness_voters(_witness_id)
    WHERE operation_id < _first_op_today
  ) result;
END
$function$
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
;

CREATE FUNCTION hafbe_backend.latest_op_id()
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN id FROM hive.operations_view ORDER BY id DESC LIMIT 1;
END
$$
;

CREATE FUNCTION hafbe_backend.parse_witness_set_props(_op_value JSON, _attr_name TEXT)
RETURNS TEXT
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN props->>1
  FROM (
    SELECT json_array_elements(_op_value->'props') AS props
  ) to_arr
  WHERE props->>0 = _attr_name;
END
$$
;

CREATE FUNCTION hafbe_backend.unpack_from_vector(_vector TEXT)
RETURNS TEXT
LANGUAGE 'plpgsql'
AS
$$
BEGIN 
  -- TODO: to be replaced by hive fork manager method
  RETURN _vector;
END
$$
;

CREATE FUNCTION hafbe_backend.get_witness_url(_witness_id INT, _last_op_id BIGINT = NULL)
RETURNS JSON
AS
$function$
BEGIN
  IF _last_op_id IS NULL THEN
    SELECT hafbe_backend.latest_op_id() INTO _last_op_id;
  END IF;

  RETURN to_json(result) FROM (
    SELECT
      CASE WHEN op_type_id = 42 AND url IS NOT NULL THEN
        hafbe_backend.unpack_from_vector(url)
      ELSE url END AS url
    FROM (
      SELECT
        CASE WHEN op_type_id = 42 AND url IS NULL THEN
          (SELECT f->>'url' FROM hafbe_backend.get_witness_url(_witness_id, op_id - 1) f)
        ELSE url END AS url,
        op_type_id
      FROM (
        SELECT
          CASE WHEN op_type_id = 42 THEN
            hafbe_backend.parse_witness_set_props(op, 'url')
          ELSE
            op->>'url'
          END AS url,
          op_type_id,
          id AS op_id
        FROM (
          SELECT
            (body::JSON)->'value' AS op,
            op_type_id, id
          FROM hive.operations_view

          JOIN (
            SELECT operation_id
            FROM hive.account_operations_view
            WHERE account_id = _witness_id AND (op_type_id = 42 OR op_type_id = 11) AND operation_id <= _last_op_id
            ORDER BY operation_id DESC
            LIMIT 1
          ) haov ON id = haov.operation_id
        ) op
        ) price
    ) recur
  ) result;
END
$function$
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
;

CREATE FUNCTION hafbe_backend.get_witness_block_size(_witness_id INT, _last_op_id BIGINT = NULL)
RETURNS JSON
AS
$function$
BEGIN
  IF _last_op_id IS NULL THEN
    SELECT hafbe_backend.latest_op_id() INTO _last_op_id;
  END IF;

  RETURN to_json(result) FROM (
    SELECT
      CASE WHEN op_type_id = 42 AND block_size IS NOT NULL THEN
        hafbe_backend.unpack_from_vector(block_size)
      ELSE block_size END AS block_size
    FROM (
      SELECT
        CASE WHEN op_type_id = 42 AND block_size IS NULL THEN
          (SELECT f->>'block_size' FROM hafbe_backend.get_witness_block_size(_witness_id, op_id - 1) f)
        ELSE block_size END AS block_size,
        op_type_id
      FROM (
        SELECT
          CASE WHEN op_type_id = 42 THEN
            hafbe_backend.parse_witness_set_props(op, 'maximum_block_size')
          ELSE
            op->'props'->>'maximum_block_size'
          END AS block_size,
          op_type_id,
          id AS op_id
        FROM (
          SELECT
            (body::JSON)->'value' AS op,
            op_type_id, id, timestamp
          FROM hive.operations_view

          JOIN (
            SELECT operation_id
            FROM hive.account_operations_view
            WHERE account_id = _witness_id AND op_type_id = ANY('{42,30,14,11}'::INT[]) AND operation_id <= _last_op_id
            ORDER BY operation_id DESC
            LIMIT 1
          ) haov ON id = haov.operation_id
        ) op
      ) price
    ) recur
  ) result;
END
$function$
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
;

CREATE FUNCTION hafbe_backend.get_witness_exchange_rate(_witness_id INT, _last_op_id BIGINT = NULL)
RETURNS JSON
AS
$function$
BEGIN
  IF _last_op_id IS NULL THEN
    SELECT hafbe_backend.latest_op_id() INTO _last_op_id;
  END IF;

  RETURN to_json(result) FROM (
    SELECT
      CASE WHEN op_type_id = 42 AND exchange_rate IS NOT NULL THEN
        hafbe_backend.unpack_from_vector(exchange_rate)
      ELSE exchange_rate END AS exchange_rate,
      timestamp
    FROM (
      SELECT
        CASE WHEN op_type_id = 42 AND exchange_rate IS NULL THEN
          (SELECT f->>'exchange_rate' FROM hafbe_backend.get_witness_exchange_rate(_witness_id, op_id - 1) f)
        ELSE exchange_rate END AS exchange_rate,
        op_type_id, timestamp
      FROM (
        SELECT
          CASE WHEN op_type_id = 42 THEN
            hafbe_backend.parse_witness_set_props(op, 'hbd_exchange_rate')
          ELSE
            op->>'exchange_rate'
          END AS exchange_rate,
          op_type_id,
          id AS op_id,
          timestamp
        FROM (
          SELECT
            (body::JSON)->'value' AS op,
            op_type_id, id, timestamp
          FROM hive.operations_view

          JOIN (
            SELECT operation_id
            FROM hive.account_operations_view
            WHERE account_id = _witness_id AND (op_type_id = 42 OR op_type_id = 7) AND operation_id <= _last_op_id
            ORDER BY operation_id DESC
            LIMIT 1
          ) haov ON id = haov.operation_id
        ) op
      ) price
    ) recur
  ) result;
END
$function$
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
;

CREATE FUNCTION hafbe_backend.get_witness_signing_key(_witness_id INT, _last_op_id BIGINT = NULL)
RETURNS JSON
AS
$function$
BEGIN
  IF _last_op_id IS NULL THEN
    SELECT hafbe_backend.latest_op_id() INTO _last_op_id;
  END IF;

  RETURN to_json(result) FROM (
    SELECT
      CASE WHEN op_type_id = 42 AND signing_key IS NULL THEN
        (SELECT f->>'signing_key' FROM hafbe_backend.get_witness_signing_key(_witness_id, op_id - 1) f)
      ELSE signing_key END AS signing_key
    FROM (
      SELECT
        CASE WHEN op_type_id = 42 AND signing_key IS NULL THEN
          hafbe_backend.parse_witness_set_props(signing_key::JSON, 'key')
        ELSE signing_key END AS signing_key,
        op_type_id, op_id
      FROM (
        SELECT
          CASE WHEN op_type_id = 42 THEN
            hafbe_backend.parse_witness_set_props(op, 'new_signing_key')
          ELSE
            op->>'block_signing_key'
          END AS signing_key,
          op_type_id,
          id AS op_id
        FROM (
          SELECT
            (body::JSON)->'value' AS op,
            op_type_id, id
          FROM hive.operations_view

          JOIN (
            SELECT operation_id
            FROM hive.account_operations_view
            WHERE account_id = _witness_id AND (op_type_id = 42 OR op_type_id = 11) AND operation_id <= _last_op_id
            ORDER BY operation_id DESC
            LIMIT 1
          ) haov ON id = haov.operation_id
        ) key_op
      ) new_key_val
    ) key_val
  ) result;
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