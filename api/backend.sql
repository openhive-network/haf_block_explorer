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
  FROM hive.operations_view hov
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

CREATE TYPE hafbe_backend.witness_voters AS (
  account TEXT,
  vests NUMERIC,
  account_vests NUMERIC,
  proxied_vests NUMERIC,
  timestamp TIMESTAMP
);

CREATE FUNCTION hafbe_backend.get_set_of_witness_voters(_witness_id INT, _limit INT, _offset INT, _order_by TEXT, _order_is TEXT)
RETURNS SETOF hafbe_backend.witness_voters
AS
$function$
BEGIN
  RETURN QUERY EXECUTE format(
    $query$

    SELECT name::TEXT, vsv.vests, vsv.account_vests, vsv.proxied_vests, vsv.timestamp
    FROM hive.accounts_view

    JOIN (
      SELECT voter_id
      FROM hafbe_app.current_witness_votes
      WHERE witness_id = _witness_id
    ) cwv ON cwv.voter_id = id

    JOIN (
      SELECT voter_id, proxied_vests + account_vests AS vests, account_vests, proxied_vests, timestamp
      FROM hafbe_views.voters_stats_view
      WHERE witness_id = %L
    ) vsv ON vsv.voter_id = id
    
    ORDER BY
      (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
      (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC
    OFFSET %L
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

CREATE FUNCTION hafbe_backend.get_witness_voters(_witness_id INT, _limit INT, _offset INT, _order_by TEXT, _order_is TEXT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS 
$$
BEGIN
  RETURN CASE WHEN arr IS NOT NULL THEN to_json(arr) ELSE '[]'::JSON END FROM (
    SELECT ARRAY(
      SELECT hafbe_backend.get_set_of_witness_voters(_witness_id, _limit, _offset, _order_by, _order_is)
    ) arr
  ) result;
END
$$
;

CREATE TYPE hafbe_backend.witnesses_by_name AS (
  witness_id INT,
  witness TEXT,
  url TEXT,
  price_feed TEXT,
  bias INT,
  feed_age INTERVAL,
  block_size INT,
  signing_key TEXT,
  version TEXT
);

CREATE FUNCTION hafbe_backend.get_set_of_witnesses_by_name(_limit INT, _offset INT, _order_is TEXT)
RETURNS SETOF hafbe_backend.witnesses_by_name
AS
$function$
BEGIN
  RETURN QUERY EXECUTE format(
    $query$

    SELECT
      witness_id, name::TEXT AS witness,
      url, price_feed, bias, feed_age, block_size, signing_key, version
    FROM hive.accounts_view hav
    JOIN hafbe_app.current_witnesses cw ON hav.id = cw.witness_id
    ORDER BY
      (CASE WHEN %L = 'desc' THEN name ELSE NULL END) DESC,
      (CASE WHEN %L = 'asc' THEN name ELSE NULL END) ASC
    OFFSET %L
    LIMIT %L

    $query$,
    _order_is, _order_is, _offset, _limit
  );
END
$function$
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
;

CREATE TYPE hafbe_backend.witnesses_by_votes AS (
  witness_id INT,
  votes NUMERIC,
  voters_num INT
);

CREATE FUNCTION hafbe_backend.get_set_of_witnesses_by_votes(_limit INT, _offset INT, _order_by TEXT, _order_is TEXT)
RETURNS SETOF hafbe_backend.witnesses_by_votes
AS
$function$
BEGIN
  RETURN QUERY EXECUTE format(
    $query$

    SELECT witness_id, votes::NUMERIC, voters_num::INT
    FROM (
      SELECT
        witness_id,
        SUM(account_vests + proxied_vests) AS votes,
        COUNT(voter_id) AS voters_num
      FROM hafbe_views.voters_stats_view
      GROUP BY witness_id
    ) vsv
    ORDER BY
      (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
      (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC
    OFFSET %L
    LIMIT %L

    $query$,
    _order_is, _order_by, _order_is, _order_by, _offset, _limit
  );
END
$function$
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
;

CREATE TYPE hafbe_backend.witnesses_by_votes_change AS (
  witness_id INT,
  votes_daily_change BIGINT,
  voters_num_daily_change INT
);

CREATE FUNCTION hafbe_backend.get_set_of_witnesses_by_votes_change(_limit INT, _offset INT, _order_by TEXT, _order_is TEXT, _today DATE)
RETURNS SETOF hafbe_backend.witnesses_by_votes_change
AS
$function$
BEGIN
  RETURN QUERY EXECUTE format(
    $query$

    SELECT witness_id, votes_daily_change::BIGINT, voters_num_daily_change::INT
    FROM (
      SELECT
        witness_id,
        SUM(CASE WHEN approve IS TRUE THEN votes ELSE -1 * votes END) AS votes_daily_change,
        SUM(CASE WHEN approve IS TRUE THEN 1 ELSE -1 END) AS voters_num_daily_change
      FROM hafbe_views.voters_stats_change_view
      WHERE timestamp >= %L
      GROUP BY witness_id
    ) vscv
    ORDER BY
      (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
      (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC
    OFFSET %L
    LIMIT %L

    $query$,
    _today, _order_is, _order_by, _order_is, _order_by, _offset, _limit
  );
END
$function$
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
;

CREATE TYPE hafbe_backend.witnesses_by_prop AS (
  witness_id INT,
  url TEXT,
  price_feed TEXT,
  bias INT,
  feed_age INTERVAL,
  block_size INT,
  signing_key TEXT,
  version TEXT
);

CREATE FUNCTION hafbe_backend.get_set_of_witnesses_by_prop(_limit INT, _offset INT, _order_by TEXT, _order_is TEXT)
RETURNS SETOF hafbe_backend.witnesses_by_prop
AS
$function$
BEGIN
  RETURN QUERY EXECUTE format(
    $query$

    SELECT
      witness_id, url, price_feed, bias, feed_age, block_size, signing_key, version
    FROM hafbe_app.current_witnesses
    WHERE %I IS NOT NULL
    ORDER BY
      (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
      (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC
    OFFSET %L
    LIMIT %L

    $query$,
    _order_by, _order_is, _order_by, _order_is, _order_by, _offset, _limit
  );
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

CREATE FUNCTION hafbe_backend.get_set_of_witnesses(_limit INT, _offset INT, _order_by TEXT, _order_is TEXT)
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

  IF _order_by = 'witness' THEN

    RETURN QUERY SELECT
      witness, url,
      COALESCE(votes, 0)::NUMERIC,
      COALESCE(votes_daily_change, 0)::BIGINT,
      COALESCE(voters_num, 0)::INT,
      COALESCE(voters_num_daily_change, 0)::INT,
      price_feed, bias, feed_age, block_size, signing_key, version
    FROM hafbe_backend.get_set_of_witnesses_by_name(_limit, _offset, _order_is) ls
    LEFT JOIN (
      SELECT
        witness_id,
        SUM(account_vests + proxied_vests) AS votes,
        COUNT(voter_id) AS voters_num
      FROM hafbe_views.voters_stats_view
      GROUP BY witness_id
    ) all_votes ON all_votes.witness_id = ls.witness_id
    LEFT JOIN (
      SELECT
        witness_id,
        SUM(CASE WHEN approve IS TRUE THEN votes ELSE -1 * votes END) AS votes_daily_change,
        SUM(CASE WHEN approve IS TRUE THEN 1 ELSE -1 END) AS voters_num_daily_change
      FROM hafbe_views.voters_stats_change_view
      WHERE timestamp >= __today
      GROUP BY witness_id
    ) todays_votes ON todays_votes.witness_id = ls.witness_id;

  ELSIF _order_by = ANY('{votes,voters_num}'::TEXT[]) THEN

    RETURN QUERY SELECT
      hav.name::TEXT, url, votes,
      COALESCE(votes_daily_change, 0)::BIGINT AS votes_daily_change,
      voters_num,
      COALESCE(voters_num_daily_change, 0)::INT AS voters_num_daily_change,
      price_feed, bias, feed_age, block_size, signing_key, version
    FROM hafbe_backend.get_set_of_witnesses_by_votes(_limit, _offset, _order_by, _order_is) ls
    JOIN hafbe_app.current_witnesses cw ON cw.witness_id = ls.witness_id
    LEFT JOIN (
      SELECT
        witness_id,
        SUM(CASE WHEN approve IS TRUE THEN votes ELSE -1 * votes END) AS votes_daily_change,
        SUM(CASE WHEN approve IS TRUE THEN 1 ELSE -1 END) AS voters_num_daily_change
      FROM hafbe_views.voters_stats_change_view
      WHERE timestamp >= __today
      GROUP BY witness_id
    ) todays_votes ON todays_votes.witness_id = ls.witness_id
    JOIN (
      SELECT name, id
      FROM hive.accounts_view
    ) hav ON hav.id = ls.witness_id;

  ELSIF _order_by = ANY('{votes_daily_change,voters_num_daily_change}') THEN

    RETURN QUERY SELECT
      hav.name::TEXT, url,
      COALESCE(votes, 0)::NUMERIC,
      votes_daily_change,
      COALESCE(voters_num, 0)::INT,
      voters_num_daily_change,
      price_feed, bias, feed_age, block_size, signing_key, version
    FROM hafbe_backend.get_set_of_witnesses_by_votes_change(_limit, _offset, _order_by, _order_is, __today) ls
    JOIN hafbe_app.current_witnesses cw ON cw.witness_id = ls.witness_id
    LEFT JOIN (
      SELECT
        witness_id,
        SUM(account_vests + proxied_vests) AS votes,
        COUNT(voter_id) AS voters_num
      FROM hafbe_views.voters_stats_view
      GROUP BY witness_id
    ) all_votes ON all_votes.witness_id = ls.witness_id
    JOIN (
      SELECT name, id
      FROM hive.accounts_view
    ) hav ON hav.id = ls.witness_id;

  ELSE

    RETURN QUERY SELECT
      hav.name::TEXT, url,
      COALESCE(votes, 0)::NUMERIC,
      COALESCE(votes_daily_change, 0)::BIGINT,
      COALESCE(voters_num, 0)::INT,
      COALESCE(voters_num_daily_change, 0)::INT,
      price_feed, bias, feed_age, block_size, signing_key, version
    FROM hafbe_backend.get_set_of_witnesses_by_prop(_limit, _offset, _order_by, _order_is) ls
    LEFT JOIN (
      SELECT
        witness_id,
        SUM(account_vests + proxied_vests) AS votes,
        COUNT(voter_id) AS voters_num
      FROM hafbe_views.voters_stats_view
      GROUP BY witness_id
    ) all_votes ON all_votes.witness_id = ls.witness_id
    LEFT JOIN (
      SELECT
        witness_id,
        SUM(CASE WHEN approve IS TRUE THEN votes ELSE -1 * votes END) AS votes_daily_change,
        SUM(CASE WHEN approve IS TRUE THEN 1 ELSE -1 END) AS voters_num_daily_change
      FROM hafbe_views.voters_stats_change_view
      WHERE timestamp >= __today
      GROUP BY witness_id
    ) todays_votes ON todays_votes.witness_id = ls.witness_id
    JOIN (
      SELECT name, id
      FROM hive.accounts_view
    ) hav ON hav.id = ls.witness_id;

  END IF;
END
$function$
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
;

CREATE FUNCTION hafbe_backend.get_witnesses(_limit INT, _offset INT, _order_by TEXT, _order_is TEXT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS 
$$
BEGIN
  RETURN CASE WHEN arr IS NOT NULL THEN to_json(arr) ELSE '[]'::JSON END FROM (
    SELECT ARRAY(
      SELECT hafbe_backend.get_set_of_witnesses(_limit, _offset, _order_by, _order_is)
    ) arr
  ) result;
END
$$
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