DROP SCHEMA IF EXISTS hafbe_backend CASCADE;

CREATE SCHEMA IF NOT EXISTS hafbe_backend;

CREATE EXTENSION IF NOT EXISTS plpython3u SCHEMA pg_catalog;

/*
general
*/

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

/*
operation types
*/

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

/*
operations
*/

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

/*
Block stats
*/

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

/*
witnesses and voters
*/

CREATE TYPE hafbe_backend.voters_stats AS (
  voter_id INT,
  account_vests NUMERIC,
  proxied_vests NUMERIC,
  timestamp TIMESTAMP
);

CREATE FUNCTION hafbe_backend.get_set_of_voters_stats(_witness_id INT)
RETURNS SETOF hafbe_backend.voters_stats
AS
$function$
BEGIN
  RETURN QUERY SELECT
    cwv.voter_id,
    SUM(COALESCE(account.vests, 0)) AS account_vests,
    SUM(COALESCE(proxied.vests, 0)) AS proxied_vests,
    cwv.timestamp
  FROM hafbe_app.current_witness_votes cwv

  LEFT JOIN (
    SELECT account_id, proxy_id
    FROM hafbe_app.current_account_proxies
    WHERE proxy = TRUE 
  ) acc_as_proxy ON acc_as_proxy.proxy_id = cwv.voter_id

  LEFT JOIN (
    SELECT vests, account_id
    FROM hafbe_app.account_vests
  ) proxied ON proxied.account_id = acc_as_proxy.account_id

  LEFT JOIN (
    SELECT account_id, proxy
    FROM hafbe_app.current_account_proxies
  ) acc_as_proxied ON acc_as_proxied.account_id = cwv.voter_id

  LEFT JOIN (
    SELECT vests, account_id
    FROM hafbe_app.account_vests
  ) account ON account.account_id = acc_as_proxied.account_id AND COALESCE(acc_as_proxied.proxy, FALSE) IS FALSE

  WHERE cwv.witness_id = _witness_id AND cwv.approve = TRUE
  GROUP BY cwv.voter_id, cwv.timestamp;
END
$function$
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
;

CREATE TYPE hafbe_backend.witness_voters AS (
  account TEXT,
  vests NUMERIC,
  account_vests NUMERIC,
  proxied_vests NUMERIC,
  timestamp TIMESTAMP
);

CREATE FUNCTION hafbe_backend.get_set_of_witness_voters(_witness_id INT, _limit INT, _order_by TEXT, _order_is TEXT)
RETURNS SETOF hafbe_backend.witness_voters
AS
$function$
BEGIN
  RETURN QUERY EXECUTE format(
    $query$

    SELECT account, vests, account_vests, proxied_vests, timestamp
    FROM (
      SELECT
        hav.name::TEXT AS account,
        proxied_vests + account_vests AS vests,
        account_vests,
        proxied_vests,
        timestamp
      FROM hafbe_backend.get_set_of_voters_stats(%L)

      JOIN (
        SELECT name, id
        FROM hive.accounts_view
      ) hav ON hav.id = voter_id
    ) voters_stats
    
    ORDER BY
      (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
      (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC
    LIMIT %L;

    $query$,
    _witness_id, _order_is, _order_by, _order_is, _order_by, _limit
  ) res;
END
$function$
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
;

CREATE FUNCTION hafbe_backend.get_witness_voters(_witness_id INT, _limit INT, _order_by TEXT, _order_is TEXT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS 
$$
BEGIN
  RETURN CASE WHEN arr IS NOT NULL THEN to_json(arr) ELSE '[]'::JSON END FROM (
    SELECT ARRAY(
      SELECT hafbe_backend.get_set_of_witness_voters(_witness_id, _limit, _order_by, _order_is)
    ) arr
  ) result;
END
$$
;

CREATE TYPE hafbe_backend.voters_stats_change AS (
  votes BIGINT,
  voters_num INT
);

CREATE FUNCTION hafbe_backend.get_set_of_voters_stats_change(_witness_id INT, _today DATE)
RETURNS SETOF hafbe_backend.voters_stats_change
AS
$function$
BEGIN
  IF _today IS NULL THEN
    RETURN QUERY SELECT 0::INT, 0::INT;
  ELSE
    RETURN QUERY SELECT
      SUM(
        COALESCE(CASE WHEN acc_as_proxy.proxy IS FALSE THEN -1 * proxied.vests ELSE proxied.vests END, 0)
          +
        COALESCE(CASE WHEN acc_as_proxied.proxy IS FALSE THEN account.vests ELSE 0 END, 0)
      )::BIGINT,
      CASE WHEN wvh.approve IS FALSE THEN -1 ELSE 1 END
    FROM hafbe_app.witness_votes_history wvh

    LEFT JOIN (
      SELECT account_id, proxy_id, proxy
      FROM hafbe_app.account_proxies_history
      WHERE timestamp >= _today
    ) acc_as_proxy ON acc_as_proxy.proxy_id = wvh.voter_id

    LEFT JOIN (
      SELECT vests, account_id
      FROM hafbe_app.account_vests
    ) proxied ON proxied.account_id = acc_as_proxy.account_id

    LEFT JOIN (
      SELECT account_id, proxy
      FROM hafbe_app.account_proxies_history
      WHERE timestamp >= _today
    ) acc_as_proxied ON acc_as_proxied.account_id = wvh.voter_id

    LEFT JOIN (
      SELECT vests, account_id
      FROM hafbe_app.account_vests
    ) account ON account.account_id = acc_as_proxied.account_id

    WHERE wvh.witness_id = _witness_id AND wvh.timestamp >= _today
    GROUP BY wvh.voter_id, wvh.timestamp, wvh.approve;
  END IF;
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
  voters_num_daily_change INT,
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
  __today DATE;
BEGIN
  IF (
    SELECT timestamp::DATE FROM hafbe_app.witness_votes_history ORDER BY timestamp DESC LIMIT 1
  ) != 'today'::DATE THEN
    __today = NULL;
  ELSE
    __today = 'today'::DATE;
  END IF;

  RETURN QUERY SELECT
    hav.name::TEXT AS witness,
    url,
    all_votes.votes::NUMERIC AS votes,
    COALESCE(todays_votes.votes, 0)::BIGINT AS votes_daily_change,
    all_votes.voters_num::INT AS voters_num,
    COALESCE(todays_votes.voters_num, 0)::INT AS voters_num_daily_change,
    feed_data->>'exchange_rate' AS price_feed,
    --(feed_data->'exchange_rate'->'quote'->>'amount')::INT - 1000 AS bias
    0 AS bias,
    (NOW() - (feed_data->>'timestamp')::TIMESTAMP)::INTERVAL AS feed_age,
    block_size::INT AS block_size,
    signing_key,
    '1.25.0' AS version
  FROM hafbe_app.current_witnesses

  JOIN LATERAL (
    SELECT
      SUM(account_vests + proxied_vests) AS votes,
      COUNT(*) AS voters_num
    FROM hafbe_backend.get_set_of_voters_stats(witness_id)
  ) all_votes ON TRUE

  JOIN LATERAL (
    SELECT
      SUM(votes) AS votes,
      SUM(voters_num) AS voters_num
    FROM hafbe_backend.get_set_of_voters_stats_change(witness_id, __today)
  ) todays_votes ON TRUE

  JOIN (
    SELECT name, id
    FROM hive.accounts_view
  ) hav ON hav.id = witness_id

  JOIN LATERAL(
    SELECT hafbe_backend.parse_and_unpack_witness_data(witness_id, 'url', '{42,11}')->>'url' AS url
  ) wd_url ON TRUE
  
  JOIN LATERAL(
    SELECT hafbe_backend.parse_and_unpack_witness_data(witness_id, 'exchange_rate', '{42,7}') AS feed_data
  ) wd_rate ON TRUE
  
  JOIN LATERAL(
    SELECT hafbe_backend.parse_and_unpack_witness_data(witness_id, 'maximum_block_size', '{42,30,14,11}')->>'maximum_block_size' AS block_size
  ) wd_size ON TRUE

  JOIN LATERAL(
    SELECT hafbe_backend.parse_and_unpack_witness_data(witness_id, 'signing_key', '{42,11}')->>'signing_key' AS signing_key
  ) wd_key ON TRUE

  ORDER BY all_votes.votes DESC
  LIMIT _limit;
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

CREATE FUNCTION hafbe_backend.parse_witness_set_props(_op_value JSON, _attr_name TEXT)
RETURNS TEXT
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __result TEXT;
BEGIN
  SELECT INTO __result
    props->>1
  FROM (
    SELECT json_array_elements(_op_value->'props') AS props
  ) to_arr
  WHERE props->>0 = _attr_name;

  IF _attr_name = 'new_signing_key' AND __result IS NULL THEN
    SELECT INTO __result
      props->>1
    FROM (
      SELECT json_array_elements(_op_value->'props') AS props
    ) to_arr
    WHERE props->>0 = 'key';
  END IF;

  RETURN __result;
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

CREATE FUNCTION hafbe_backend.parse_and_unpack_witness_data(_witness_id INT, _attr_name TEXT, _op_type_array INT[], _last_op_id BIGINT = NULL)
RETURNS JSON
AS
$function$
DECLARE
  __most_recent_op RECORD;
  __result TEXT;
  __witness_set_props_attr_name TEXT;
BEGIN
  IF _last_op_id <= 0 THEN
    RETURN json_build_object (
      _attr_name, NULL
    );
  END IF;

  IF _last_op_id IS NULL THEN
    SELECT id FROM hive.operations_view ORDER BY id DESC LIMIT 1 INTO _last_op_id;
  END IF;

  SELECT INTO __most_recent_op
    (body::JSON)->'value' AS value,
    op_type_id, id, timestamp
  FROM hive.operations_view
  JOIN (
    SELECT operation_id
    FROM hive.account_operations_view
    WHERE account_id = _witness_id AND op_type_id = ANY(_op_type_array)
    ORDER BY operation_id DESC
  ) haov ON haov.operation_id = id
  LIMIT 1;

  IF _attr_name = 'url' THEN
    SELECT __most_recent_op.value->>'url' INTO __result;
    SELECT 'url' INTO __witness_set_props_attr_name;
  ELSIF _attr_name = 'exchange_rate' THEN
    SELECT __most_recent_op.value->>'exchange_rate' INTO __result;
    SELECT 'hbd_exchange_rate' INTO __witness_set_props_attr_name;
  ELSIF _attr_name = 'maximum_block_size' THEN
    SELECT __most_recent_op.value->'props'->>'maximum_block_size' INTO __result;
    SELECT 'maximum_block_size' INTO __witness_set_props_attr_name;
  ELSIF _attr_name = 'signing_key' THEN
    SELECT __most_recent_op.value->>'block_signing_key' INTO __result;
    SELECT 'new_signing_key' INTO __witness_set_props_attr_name;
  END IF;

  IF __result IS NULL AND __most_recent_op.op_type_id = 42 THEN
    SELECT hafbe_backend.parse_witness_set_props(__most_recent_op.value, __witness_set_props_attr_name) INTO __result;
  ELSIF __result IS NULL AND __most_recent_op.op_type_id != 42 THEN
    RETURN hafbe_backend.parse_and_unpack_witness_data(
      _witness_id, __witness_set_props_attr_name, _op_type_array, __most_recent_op.id - 1)
    ;
  END IF;

  RETURN json_build_object(
    _attr_name, __result,
    'timestamp', __most_recent_op.timestamp
  );
END
$function$
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
;

/*
account data
*/

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