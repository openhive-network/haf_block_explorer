DROP SCHEMA IF EXISTS hafbe_backend CASCADE;

CREATE SCHEMA IF NOT EXISTS hafbe_backend AUTHORIZATION hafbe_owner;

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

CREATE FUNCTION hafbe_backend.get_set_of_op_types()
RETURNS SETOF hafbe_types.op_types
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN QUERY SELECT
    id, name, is_virtual
  FROM hive.operation_types
  ORDER BY id ASC;
END
$$
;

CREATE FUNCTION hafbe_backend.get_set_of_acc_op_types(_account_id INT)
RETURNS SETOF hafbe_types.op_types
AS
$function$
BEGIN
  RETURN QUERY SELECT
    aoc.op_type_id, hot.name, hot.is_virtual
  FROM hafbe_app.account_operation_cache aoc
  JOIN (
    SELECT id, name, is_virtual
    FROM hive.operation_types
  ) hot ON hot.id = aoc.op_type_id
  WHERE aoc.account_id = _account_id
  ORDER BY aoc.op_type_id ASC;
END
$function$
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
;

CREATE FUNCTION hafbe_backend.get_set_of_block_op_types(_block_num INT)
RETURNS SETOF hafbe_types.op_types
AS
$function$
BEGIN
  RETURN QUERY SELECT
    hov.op_type_id, hot.name, hot.is_virtual
  FROM hive.operations_view hov
  JOIN  (
    SELECT id, name, is_virtual
    FROM hive.operation_types
  ) hot ON hot.id = hov.op_type_id
  WHERE hov.block_num = _block_num
  ORDER BY hov.op_type_id ASC;
END
$function$
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
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

CREATE FUNCTION hafbe_backend.get_set_of_ops_by_account(_account_id INT, _top_op_id BIGINT, _limit BIGINT, _filter SMALLINT[], _date_start TIMESTAMP, _date_end TIMESTAMP)
RETURNS SETOF hafbe_types.operations 
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

CREATE FUNCTION hafbe_backend.get_set_of_ops_by_block(_block_num INT, _top_op_id BIGINT, _limit BIGINT, _filter SMALLINT[])
RETURNS SETOF hafbe_types.operations 
AS
$function$
DECLARE
  __filter_ops BOOLEAN = ((SELECT array_length(_filter, 1)) IS NULL);
BEGIN
  RETURN QUERY SELECT
    encode(htv.trx_hash, 'hex')::TEXT,
    _block_num::INT,
    hov.trx_in_block::INT,
    hov.op_pos::INT,
    hot.is_virtual::BOOLEAN,
    hov.timestamp::TEXT,
    hov.body::JSON,
    hov.id::BIGINT,
    NULL::BIGINT
  FROM hive.operations_view hov
  JOIN (
    SELECT id, is_virtual
    FROM hive.operation_types
  ) hot ON hot.id = hov.op_type_id
  JOIN (
    SELECT trx_hash, block_num, trx_in_block
    FROM hive.transactions_view
  ) htv ON htv.block_num = hov.block_num AND htv.trx_in_block = hov.trx_in_block
  WHERE
    hov.block_num = _block_num AND
    hov.id <= _top_op_id AND (
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

/*
Block stats
*/

CREATE FUNCTION hafbe_backend.get_block(_block_num INT)
RETURNS JSON
AS
$function$
BEGIN
  RETURN to_json(res) FROM (
    SELECT
      hbv.num AS block_num,
      encode(hbv.hash, 'hex')::TEXT AS block_hash,
      hbv.created_at AS timestamp,
      hav.name AS witness,
      hbv.signing_key
    FROM hive.accounts_view hav
    JOIN (
      SELECT num, hash, created_at, producer_account_id, signing_key
      FROM hive.blocks_view
      WHERE num = _block_num
      LIMIT 1
    ) hbv ON hbv.producer_account_id = hav.id
  ) res;
END
$function$
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
;

/*
witness voters
*/

CREATE FUNCTION hafbe_backend.get_set_of_witness_voters_by_name(_witness_id INT, _limit INT, _offset INT, _order_is TEXT)
RETURNS SETOF hafbe_types.witness_voters_by_name
AS
$function$
BEGIN
  RETURN QUERY EXECUTE format(
    $query$

    SELECT cwv.voter_id, hav.name::TEXT AS voter
    FROM hafbe_app.current_witness_votes cwv
    JOIN LATERAL (
      SELECT name
      FROM hive.accounts_view
      WHERE id = cwv.voter_id
    ) hav ON TRUE
    WHERE cwv.witness_id = %L
    ORDER BY
      (CASE WHEN %L = 'desc' THEN hav.name ELSE NULL END) DESC,
      (CASE WHEN %L = 'asc' THEN hav.name ELSE NULL END) ASC
    OFFSET %L
    LIMIT %L

    $query$,
    _witness_id, _order_is, _order_is, _offset, _limit
  );
END
$function$
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
;

CREATE FUNCTION hafbe_backend.get_set_of_witness_voters_by_vests(_witness_id INT, _limit INT, _offset INT, _order_by TEXT, _order_is TEXT)
RETURNS SETOF hafbe_types.witness_voters_by_vests
AS
$function$
BEGIN
  RETURN QUERY EXECUTE format(
    $query$

    SELECT voter_id, vests, account_vests::NUMERIC, proxied_vests, timestamp
    FROM hafbe_views.voters_stats_view
    WHERE witness_id = %L
    ORDER BY
      (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
      (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC
    OFFSET %L
    LIMIT %L

    $query$,
    _witness_id, _order_is, _order_by, _order_is, _order_by, _offset, _limit
  );
END
$function$
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
;

CREATE FUNCTION hafbe_backend.get_set_of_witness_voters(_witness_id INT, _limit INT, _offset INT, _order_by TEXT, _order_is TEXT)
RETURNS SETOF hafbe_types.witness_voters
AS
$function$
BEGIN
  IF _order_by = 'voter' THEN

    RETURN QUERY EXECUTE format(
      $query$

      SELECT voter, vsv.vests, vsv.account_vests::NUMERIC, vsv.proxied_vests, vsv.timestamp
      FROM hafbe_backend.get_set_of_witness_voters_by_name(%L, %L, %L, %L) ls
      JOIN (
        SELECT voter_id, vests, account_vests, proxied_vests, timestamp
        FROM hafbe_views.voters_stats_view
        WHERE witness_id = %L
      ) vsv ON vsv.voter_id = ls.voter_id
      ORDER BY
        (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
        (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC
      ;

      $query$,
      _witness_id, _limit, _offset, _order_is,
      _witness_id, _order_is, _order_by, _order_is, _order_by
    ) res;

  ELSIF _order_by = ANY('{vests,account_vests,proxied_vests,timestamp}'::TEXT[]) THEN

    RETURN QUERY EXECUTE format(
      $query$

      SELECT hav.name::TEXT, ls.vests, ls.account_vests, ls.proxied_vests, ls.timestamp
      FROM hafbe_backend.get_set_of_witness_voters_by_vests(%L, %L, %L, %L, %L) ls
      JOIN (
        SELECT id, name
        FROM hive.accounts_view
      ) hav ON hav.id = ls.voter_id
      ORDER BY
        (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
        (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC
      ;

      $query$,
      _witness_id, _limit, _offset, _order_by, _order_is,
      _order_is, _order_by, _order_is, _order_by
    ) res;

  END IF;
END
$function$
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
;

/*
witness voters change
*/

CREATE FUNCTION hafbe_backend.get_todays_date()
RETURNS DATE
LANGUAGE 'plpgsql'
AS
$$
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
  RETURN __today;
END
$$
;

CREATE FUNCTION hafbe_backend.get_set_of_witness_voters_daily_change_by_name(_witness_id INT, _limit INT, _offset INT, _order_is TEXT, _today DATE)
RETURNS SETOF hafbe_types.witness_voters_daily_change_by_name
AS
$function$
BEGIN
  RETURN QUERY EXECUTE format(
    $query$

    SELECT wvh.witness_id, wvh.voter_id, hav.name::TEXT, wvh.approve
    FROM hafbe_app.witness_votes_history wvh
    JOIN LATERAL (
      SELECT name
      FROM hive.accounts_view
      WHERE id = wvh.voter_id
    ) hav ON TRUE
    WHERE wvh.witness_id = %L AND wvh.timestamp >= %L
    ORDER BY
      (CASE WHEN %L = 'desc' THEN hav.name ELSE NULL END) DESC,
      (CASE WHEN %L = 'asc' THEN hav.name ELSE NULL END) ASC
    OFFSET %L
    LIMIT %L

    $query$,
    _witness_id, _today,
    _order_is, _order_is, _offset, _limit
  );
END
$function$
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
;

CREATE FUNCTION hafbe_backend.get_set_of_witness_voters_daily_change_by_vests(_witness_id INT, _limit INT, _offset INT, _order_by TEXT, _order_is TEXT, _today DATE)
RETURNS SETOF hafbe_types.witness_voters_daily_change_by_vests
AS
$function$
BEGIN
  RETURN QUERY EXECUTE format(
    $query$

    SELECT voter_id, vests::BIGINT, account_vests::BIGINT, proxied_vests::BIGINT, timestamp, approve
    FROM hafbe_views.voters_stats_change_view
    WHERE witness_id = %L AND timestamp >= %L
    ORDER BY
      (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
      (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC
    OFFSET %L
    LIMIT %L

    $query$,
    _witness_id, _today,
    _order_is, _order_by, _order_is, _order_by, _offset, _limit
  );
END
$function$
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
;

CREATE FUNCTION hafbe_backend.get_set_of_witness_voters_daily_change(_witness_id INT, _limit INT, _offset INT, _order_by TEXT, _order_is TEXT)
RETURNS SETOF hafbe_types.witness_voters_daily_change
AS
$function$
DECLARE
  __today DATE;
BEGIN
  SELECT hafbe_backend.get_todays_date() INTO __today;

  IF _order_by = 'voter' THEN

    RETURN QUERY EXECUTE format(
      $query$

      SELECT ls.voter, ls.approve, vscv.vests::BIGINT, vscv.account_vests::BIGINT, vscv.proxied_vests::BIGINT, vscv.timestamp
      FROM hafbe_backend.get_set_of_witness_voters_daily_change_by_name(%L, %L, %L, %L, %L) ls
      JOIN (
        SELECT voter_id, vests, account_vests, proxied_vests, timestamp
        FROM hafbe_views.voters_stats_change_view vscv
        WHERE witness_id = %L AND timestamp >= %L
      ) vscv ON vscv.voter_id = ls.voter_id
      ORDER BY
        (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
        (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC
      ;

      $query$,
      _witness_id, _limit, _offset, _order_is, __today,
      _witness_id, __today,
      _order_is, _order_by, _order_is, _order_by
    ) res;

  ELSIF _order_by = ANY('{vests,account_vests,proxied_vests,timestamp}'::TEXT[]) THEN

    RETURN QUERY EXECUTE format(
      $query$

      SELECT hav.name::TEXT, ls.approve, ls.vests, ls.account_vests, ls.proxied_vests, ls.timestamp
      FROM hafbe_backend.get_set_of_witness_voters_daily_change_by_vests(%L, %L, %L, %L, %L, %L) ls
      JOIN (
        SELECT id, name
        FROM hive.accounts_view
      ) hav ON hav.id = ls.voter_id
      ORDER BY
        (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
        (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC
      ;

      $query$,
      _witness_id, _limit, _offset, _order_by, _order_is, __today,
      _order_is, _order_by, _order_is, _order_by
    ) res;

  END IF;
END
$function$
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
;

/*
witnesses
*/

CREATE FUNCTION hafbe_backend.get_set_of_witnesses_by_name(_limit INT, _offset INT, _order_is TEXT)
RETURNS SETOF hafbe_types.witnesses_by_name
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

CREATE FUNCTION hafbe_backend.get_set_of_witnesses_by_votes(_limit INT, _offset INT, _order_by TEXT, _order_is TEXT)
RETURNS SETOF hafbe_types.witnesses_by_votes
AS
$function$
BEGIN
  RETURN QUERY EXECUTE format(
    $query$
    SELECT witness_id, votes, voters_num
    FROM (
      SELECT
        vsv.witness_id,
        SUM(vsv.vests) AS votes,
        COUNT(1)::INT AS voters_num
      FROM hafbe_views.voters_stats_view vsv
      GROUP BY vsv.witness_id
    ) votes_sum
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

CREATE FUNCTION hafbe_backend.get_set_of_witnesses_by_votes_change(_limit INT, _offset INT, _order_by TEXT, _order_is TEXT, _today DATE)
RETURNS SETOF hafbe_types.witnesses_by_votes_change
AS
$function$
BEGIN
  RETURN QUERY EXECUTE format(
    $query$

    SELECT 
      witness_id,
      SUM(vests)::BIGINT AS votes_daily_change,
      COUNT(1)::INT AS voters_num_daily_change
    FROM hafbe_views.voters_stats_change_view vscv
    WHERE timestamp >= %L
    GROUP BY witness_id
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

CREATE FUNCTION hafbe_backend.get_set_of_witnesses_by_prop(_limit INT, _offset INT, _order_by TEXT, _order_is TEXT)
RETURNS SETOF hafbe_types.witnesses_by_prop
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

CREATE FUNCTION hafbe_backend.get_set_of_witnesses(_limit INT, _offset INT, _order_by TEXT, _order_is TEXT)
RETURNS SETOF hafbe_types.witnesses
AS
$function$
DECLARE
  __today DATE;
BEGIN
  SELECT hafbe_backend.get_todays_date() INTO __today;

  IF _order_by = 'witness' THEN

    RETURN QUERY EXECUTE format(
      $query$
      
      SELECT
        witness, url,
        COALESCE(all_votes.votes, 0)::NUMERIC,
        COALESCE(todays_votes.votes_daily_change, 0)::BIGINT,
        COALESCE(all_votes.voters_num, 0)::INT,
        COALESCE(todays_votes.voters_num_daily_change, 0)::INT,
        price_feed, bias, feed_age, block_size, signing_key, version
      FROM hafbe_backend.get_set_of_witnesses_by_name(%L, %L, %L) ls
      LEFT JOIN LATERAL (
        SELECT
          vsv.witness_id,
          SUM(vsv.vests) AS votes,
          COUNT(1) AS voters_num
        FROM hafbe_views.voters_stats_view vsv
        WHERE vsv.witness_id = ls.witness_id
        GROUP BY vsv.witness_id
      ) all_votes ON all_votes.witness_id = ls.witness_id
      LEFT JOIN LATERAL (
        SELECT 
          vscv.witness_id,
          SUM(vscv.vests) AS votes_daily_change,
          COUNT(1) AS voters_num_daily_change
        FROM hafbe_views.voters_stats_change_view vscv
        WHERE vscv.timestamp >= %L AND vscv.witness_id = ls.witness_id
        GROUP BY vscv.witness_id
      ) todays_votes ON TRUE
      ORDER BY
        (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
        (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC

      $query$,
      _limit, _offset, _order_is, __today,
      _order_is, _order_by, _order_is, _order_by
    );

  ELSIF _order_by = ANY('{votes,voters_num}'::TEXT[]) THEN

    RETURN QUERY EXECUTE format(
      $query$

      SELECT
        hav.name::TEXT, url,
        ls.votes,
        COALESCE(todays_votes.votes_daily_change, 0)::BIGINT AS votes_daily_change,
        ls.voters_num,
        COALESCE(todays_votes.voters_num_daily_change, 0)::INT AS voters_num_daily_change,
        price_feed, bias, feed_age, block_size, signing_key, version
      FROM hafbe_backend.get_set_of_witnesses_by_votes(%L, %L, %L, %L) ls
      JOIN hafbe_app.current_witnesses cw ON cw.witness_id = ls.witness_id
      LEFT JOIN LATERAL (
        SELECT 
          vscv.witness_id,
          SUM(vscv.vests) AS votes_daily_change,
          COUNT(1) AS voters_num_daily_change
        FROM hafbe_views.voters_stats_change_view vscv
        WHERE vscv.timestamp >= %L AND vscv.witness_id = ls.witness_id
        GROUP BY vscv.witness_id
      ) todays_votes ON TRUE
      JOIN (
        SELECT name, id
        FROM hive.accounts_view
      ) hav ON hav.id = ls.witness_id
      ORDER BY
        (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
        (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC

      $query$,
      _limit, _offset, _order_by, _order_is, __today,
      _order_is, _order_by, _order_is, _order_by
    );

  ELSIF _order_by = ANY('{votes_daily_change,voters_num_daily_change}') THEN

    RETURN QUERY EXECUTE format(
      $query$

      SELECT
        hav.name::TEXT, url,
        all_votes.votes::NUMERIC,
        ls.votes_daily_change,
        all_votes.voters_num::INT,
        ls.voters_num_daily_change,
        price_feed, bias, feed_age, block_size, signing_key, version
      FROM hafbe_backend.get_set_of_witnesses_by_votes_change(%L, %L, %L, %L, %L) ls
      JOIN hafbe_app.current_witnesses cw ON cw.witness_id = ls.witness_id
      JOIN LATERAL (
        SELECT
          vsv.witness_id,
          SUM(vsv.vests) AS votes,
          COUNT(1) AS voters_num
        FROM hafbe_views.voters_stats_view vsv
        WHERE vsv.witness_id = ls.witness_id
        GROUP BY vsv.witness_id
      ) all_votes ON all_votes.witness_id = ls.witness_id
      JOIN (
        SELECT name, id
        FROM hive.accounts_view
      ) hav ON hav.id = ls.witness_id
      ORDER BY
        (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
        (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC

      $query$,
      _limit, _offset, _order_by, _order_is, __today,
      _order_is, _order_by, _order_is, _order_by
    );

  ELSE

    RETURN QUERY EXECUTE format(
      $query$
      
      SELECT
        hav.name::TEXT, url,
        COALESCE(all_votes.votes, 0)::NUMERIC,
        COALESCE(todays_votes.votes_daily_change, 0)::BIGINT,
        COALESCE(all_votes.voters_num, 0)::INT,
        COALESCE(todays_votes.voters_num_daily_change, 0)::INT,
        price_feed, bias, feed_age, block_size, signing_key, version
      FROM hafbe_backend.get_set_of_witnesses_by_prop(%L, %L, %L, %L) ls
      LEFT JOIN LATERAL (
        SELECT
          vsv.witness_id,
          SUM(vsv.vests) AS votes,
          COUNT(1) AS voters_num
        FROM hafbe_views.voters_stats_view vsv
        WHERE vsv.witness_id = ls.witness_id
        GROUP BY vsv.witness_id
      ) all_votes ON all_votes.witness_id = ls.witness_id
      LEFT JOIN LATERAL (
        SELECT 
          vscv.witness_id,
          SUM(vscv.vests) AS votes_daily_change,
          COUNT(1) AS voters_num_daily_change
        FROM hafbe_views.voters_stats_change_view vscv
        WHERE vscv.timestamp >= %L AND vscv.witness_id = ls.witness_id
        GROUP BY vscv.witness_id
      ) todays_votes ON TRUE
      JOIN (
        SELECT name, id
        FROM hive.accounts_view
      ) hav ON hav.id = ls.witness_id
      ORDER BY
        (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
        (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC

      $query$,
      _limit, _offset, _order_by, _order_is, __today,
      _order_is, _order_by, _order_is, _order_by
    );

  END IF;
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