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
  RETURN QUERY WITH op_types_cte AS (
    SELECT id
    FROM hive.operation_types hot
    WHERE (
      SELECT EXISTS (
        SELECT 1 FROM hive.account_operations_view haov WHERE haov.account_id = _account_id AND haov.op_type_id = hot.id
      )
    )
  )

  SELECT cte.id, hot.name, hot.is_virtual
  FROM op_types_cte cte
  JOIN hive.operation_types hot ON hot.id = cte.id;
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
  RETURN QUERY SELECT DISTINCT ON (hov.op_type_id)
    hov.op_type_id, hot.name, hot.is_virtual
  FROM hive.operations_view hov
  JOIN hive.operation_types hot ON hot.id = hov.op_type_id
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

CREATE FUNCTION hafbe_backend.get_set_of_ops_by_account(_account_id INT, _top_op_id INT, _limit INT, _filter SMALLINT[], _date_start TIMESTAMP, _date_end TIMESTAMP)
RETURNS SETOF hafbe_types.operations
AS
$function$
DECLARE
  __no_ops_filter BOOLEAN = ((SELECT array_length(_filter, 1)) IS NULL);
  __no_start_date BOOLEAN = (_date_start IS NULL);
  __no_end_date BOOLEAN = (_date_end IS NULL);
  __no_filters BOOLEAN;
  __subq_limit INT;
  __lastest_account_op_seq_no INT;
  __block_start INT;
  __block_end INT;
BEGIN
  IF __no_ops_filter AND __no_start_date AND __no_end_date THEN
    SELECT TRUE INTO __no_filters;
    SELECT NULL INTO __subq_limit;
    SELECT INTO __lastest_account_op_seq_no
      account_op_seq_no FROM hive.account_operations_view WHERE account_id = _account_id ORDER BY account_op_seq_no DESC LIMIT 1;
    SELECT INTO _top_op_id
      CASE WHEN __lastest_account_op_seq_no < _top_op_id THEN __lastest_account_op_seq_no ELSE _top_op_id END; 
  ELSE
    SELECT FALSE INTO __no_filters;
    SELECT _limit INTO __subq_limit;
  END IF;

  IF __no_start_date IS FALSE THEN
    SELECT num FROM hive.blocks_view hbv WHERE hbv.created_at >= _date_start ORDER BY created_at ASC LIMIT 1 INTO __block_start;
  END IF;
  IF __no_end_date IS FALSE THEN
    SELECT num FROM hive.blocks_view hbv WHERE hbv.created_at < _date_end ORDER BY created_at DESC LIMIT 1 INTO __block_end;
  END IF;

  RETURN QUERY EXECUTE format(
    $query$
    
    SELECT
      encode(htv.trx_hash, 'hex'),
      ls.block_num,
      hov.trx_in_block,
      hov.op_pos,
      hot.is_virtual,
      hov.timestamp::TEXT,
      hov.body::JSON,
      ls.operation_id,
      ls.account_op_seq_no
    FROM (
      SELECT haov.operation_id, haov.op_type_id, haov.block_num, haov.account_op_seq_no
      FROM hive.account_operations_view haov
      WHERE
        haov.account_id = %L::INT AND 
        haov.account_op_seq_no <= %L::INT AND
        (NOT %L OR haov.account_op_seq_no > %L::INT - %L::INT) AND
        (%L OR haov.op_type_id = ANY(%L)) AND
        (%L OR haov.block_num >= %L::INT) AND
        (%L OR haov.block_num < %L::INT)
      ORDER BY haov.operation_id DESC
      LIMIT %L
    ) ls
    JOIN hive.operations_view hov ON hov.id = ls.operation_id
    JOIN hive.operation_types hot ON hot.id = ls.op_type_id
    LEFT JOIN hive.transactions_view htv ON htv.block_num = ls.block_num AND htv.trx_in_block = hov.trx_in_block
    ORDER BY ls.operation_id DESC;

    $query$,
    _account_id,
    _top_op_id,
    __no_filters, _top_op_id, _limit,
    __no_ops_filter, _filter,
    __no_start_date, __block_start,
    __no_end_date, __block_end,
    __subq_limit
  ) res;
END
$function$
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
;

CREATE FUNCTION hafbe_backend.get_set_of_ops_by_block(_block_num INT, _top_op_id BIGINT, _limit INT, _filter SMALLINT[])
RETURNS SETOF hafbe_types.operations 
AS
$function$
DECLARE
  __no_ops_filter BOOLEAN = ((SELECT array_length(_filter, 1)) IS NULL);
BEGIN
  RETURN QUERY SELECT
    encode(htv.trx_hash, 'hex'),
    ls.block_num,
    ls.trx_in_block,
    ls.op_pos,
    hot.is_virtual,
    ls.timestamp::TEXT,
    ls.body::JSON,
    ls.id,
    NULL::INT
  FROM (
    SELECT hov.id, hov.trx_in_block, hov.op_pos, hov.timestamp, hov.body, hov.op_type_id, hov.block_num
    FROM hive.operations_view hov
    WHERE
      hov.block_num = _block_num AND
      hov.id <= _top_op_id AND 
      (__no_ops_filter OR hov.op_type_id = ANY(_filter))
    ORDER BY hov.id DESC
    LIMIT _limit
  ) ls
  JOIN hive.operation_types hot ON hot.id = ls.op_type_id
  LEFT JOIN hive.transactions_view htv ON htv.block_num = ls.block_num AND htv.trx_in_block = ls.trx_in_block
  ORDER BY ls.id DESC;
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

CREATE FUNCTION hafbe_backend.get_set_of_block_data(_block_num INT)
RETURNS SETOF hafbe_types.block
AS
$function$
BEGIN
  RETURN QUERY SELECT
    hbv.num,
    encode(hbv.hash, 'hex'),
    hbv.created_at::TEXT,
    hav.name::TEXT,
    hbv.signing_key
  FROM hive.accounts_view hav
  JOIN (
    SELECT num, hash, created_at, producer_account_id, signing_key
    FROM hive.blocks_view
    WHERE num = _block_num
    LIMIT 1
  ) hbv ON hbv.producer_account_id = hav.id;
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

CREATE FUNCTION hafbe_backend.get_witness_voters_num(_witness_id INT)
RETURNS INT
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN COUNT(1) FROM hafbe_app.current_witness_votes WHERE witness_id = _witness_id;
END
$$
;

CREATE FUNCTION hafbe_backend.get_set_of_witness_voters_in_vests(_witness_id INT, _limit INT, _offset INT, _order_by TEXT, _order_is TEXT)
RETURNS SETOF hafbe_types.witness_voters_in_vests
AS
$function$
BEGIN
  IF _order_by = 'voter' THEN

    RETURN QUERY EXECUTE format(
      $query$

      WITH limited_set AS (
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
      )

      SELECT ls.voter, vsv.vests, vsv.account_vests::NUMERIC, vsv.proxied_vests, vsv.timestamp
      FROM limited_set ls

      JOIN (
        SELECT voter_id, vests, account_vests, proxied_vests, timestamp
        FROM hafbe_app.witness_voters_stats_cache
        WHERE witness_id = %L
      ) vsv ON vsv.voter_id = ls.voter_id
      ORDER BY
        (CASE WHEN %L = 'desc' THEN ls.voter ELSE NULL END) DESC,
        (CASE WHEN %L = 'asc' THEN ls.voter ELSE NULL END) ASC
      ;

      $query$,
      _witness_id, _order_is, _order_is, _offset, _limit,
      _witness_id, _order_is, _order_is
    ) res;

  ELSE

    RETURN QUERY EXECUTE format(
      $query$

      WITH limited_set AS (
        SELECT voter_id, vests, account_vests, proxied_vests, timestamp
        FROM hafbe_app.witness_voters_stats_cache
        WHERE witness_id = %L
        ORDER BY
          (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
          (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC
        OFFSET %L
        LIMIT %L        
      )

      SELECT hav.name::TEXT, ls.vests, ls.account_vests, ls.proxied_vests, ls.timestamp
      FROM limited_set ls
      JOIN hive.accounts_view hav ON hav.id = ls.voter_id
      ORDER BY
        (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
        (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC
      ;

      $query$,
      _witness_id, _order_is, _order_by, _order_is, _order_by, _offset, _limit,
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

CREATE FUNCTION hafbe_backend.get_set_of_witness_voters_in_hp(_witness_id INT, _limit INT, _offset INT, _order_by TEXT, _order_is TEXT)
RETURNS SETOF hafbe_types.witness_voters_in_hp
AS
$function$
BEGIN
  RETURN QUERY SELECT account, hive_power, account_hive_power, proxied_hive_power, timestamp
  FROM hafbe_backend.get_set_of_witness_voters_in_vests(_witness_id, _limit, _offset, _order_by, _order_is)
  JOIN LATERAL (
    SELECT arr_hp[1] AS hive_power, arr_hp[2] AS account_hive_power, arr_hp[3] AS proxied_hive_power
    FROM (
      SELECT array_agg(hp) AS arr_hp
      FROM hafbe_backend.vests_to_hive_power(vests, account_vests, proxied_vests) hp
    ) to_arr
  ) conv ON TRUE;
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

CREATE FUNCTION hafbe_backend.get_set_of_witness_voters_daily_change_in_vests(_witness_id INT, _limit INT, _offset INT, _order_by TEXT, _order_is TEXT)
RETURNS SETOF hafbe_types.witness_voters_daily_change_in_vests
AS
$function$
DECLARE
  __today DATE;
BEGIN
  SELECT hafbe_backend.get_todays_date() INTO __today;

  IF _order_by = 'voter' THEN

    RETURN QUERY EXECUTE format(
      $query$

      WITH limited_set AS (
        SELECT wvh.voter_id, hav.name::TEXT AS voter, wvh.approve
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
      )

      SELECT
        ls.voter, ls.approve,
        COALESCE(wvcc.vests, 0)::BIGINT,
        COALESCE(wvcc.account_vests, 0)::BIGINT,
        COALESCE(wvcc.proxied_vests, 0)::BIGINT,
        wvcc.timestamp
      FROM limited_set ls
      LEFT JOIN (
        SELECT voter_id, vests, account_vests, proxied_vests, timestamp
        FROM hafbe_app.witness_voters_stats_change_cache
        WHERE witness_id = %L
      ) wvcc ON wvcc.voter_id = ls.voter_id
      ORDER BY
        (CASE WHEN %L = 'desc' THEN ls.voter ELSE NULL END) DESC,
        (CASE WHEN %L = 'asc' THEN ls.voter ELSE NULL END) ASC
      ;

      $query$,
      _witness_id, __today,
      _order_is, _order_is, _offset, _limit,
      _witness_id,
      _order_is, _order_is
    ) res;

  ELSE

    RETURN QUERY EXECUTE format(
      $query$

      WITH limited_set AS (
        SELECT voter_id, vests::BIGINT, account_vests::BIGINT, proxied_vests::BIGINT, timestamp, approve
        FROM hafbe_app.witness_voters_stats_change_cache
        WHERE witness_id = %L
        ORDER BY
          (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
          (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC
        OFFSET %L
        LIMIT %L
      )

      SELECT hav.name::TEXT, ls.approve, ls.vests, ls.account_vests, ls.proxied_vests, ls.timestamp
      FROM limited_set ls
      JOIN hive.accounts_view hav ON hav.id = ls.voter_id
      ORDER BY
        (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
        (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC
      ;

      $query$,
      _witness_id,
      _order_is, _order_by, _order_is, _order_by, _offset, _limit,
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

CREATE FUNCTION hafbe_backend.get_set_of_witness_voters_daily_change_in_hp(_witness_id INT, _limit INT, _offset INT, _order_by TEXT, _order_is TEXT)
RETURNS SETOF hafbe_types.witness_voters_in_hp
AS
$function$
BEGIN
  RETURN QUERY SELECT account, hive_power, account_hive_power, proxied_hive_power, timestamp
  FROM hafbe_backend.get_set_of_witness_voters_daily_change_in_vests(_witness_id, _limit, _offset, _order_by, _order_is)
  JOIN LATERAL (
    SELECT arr_hp[1] AS hive_power, arr_hp[2] AS account_hive_power, arr_hp[3] AS proxied_hive_power
    FROM (
      SELECT array_agg(hp) AS arr_hp
      FROM hafbe_backend.vests_to_hive_power(vests, account_vests, proxied_vests) hp
    ) to_arr
  ) conv ON TRUE;
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

CREATE FUNCTION hafbe_backend.get_set_of_witnesses_in_vests(_limit INT, _offset INT, _order_by TEXT, _order_is TEXT)
RETURNS SETOF hafbe_types.witnesses_in_vests
AS
$function$
DECLARE
  __today DATE;
BEGIN
  SELECT hafbe_backend.get_todays_date() INTO __today;

  IF _order_by = 'witness' THEN

    RETURN QUERY EXECUTE format(
      $query$

      WITH limited_set AS (
        SELECT
          cw.witness_id, hav.name::TEXT AS witness,
          cw.url, cw.price_feed, cw.bias,
          (NOW() - cw.feed_updated_at)::INTERVAL AS feed_age,
          cw.block_size, cw.signing_key, cw.version
        FROM hive.accounts_view hav
        JOIN hafbe_app.current_witnesses cw ON hav.id = cw.witness_id
        ORDER BY
          (CASE WHEN %L = 'desc' THEN hav.name ELSE NULL END) DESC,
          (CASE WHEN %L = 'asc' THEN hav.name ELSE NULL END) ASC
        OFFSET %L
        LIMIT %L
      )

      SELECT
        ls.witness, all_votes.rank, ls.url,
        COALESCE(all_votes.votes, 0)::NUMERIC,
        COALESCE(todays_votes.votes_daily_change, 0)::BIGINT,
        COALESCE(all_votes.voters_num, 0)::INT,
        COALESCE(todays_votes.voters_num_daily_change, 0)::INT,
        ls.price_feed, ls.bias, ls.feed_age, ls.block_size, ls.signing_key, ls.version
      FROM limited_set ls
      LEFT JOIN hafbe_app.witness_votes_cache all_votes ON all_votes.witness_id = ls.witness_id 
      LEFT JOIN LATERAL (
        SELECT wvcc.witness_id, wvcc.votes_daily_change, wvcc.voters_num_daily_change
        FROM hafbe_app.witness_votes_change_cache wvcc
        WHERE wvcc.witness_id = ls.witness_id
        GROUP BY wvcc.witness_id
      ) todays_votes ON TRUE
      ORDER BY
        (CASE WHEN %L = 'desc' THEN witness ELSE NULL END) DESC,
        (CASE WHEN %L = 'asc' THEN witness ELSE NULL END) ASC

      $query$,
      _order_is, _order_is, _offset, _limit,
      _order_is, _order_is
    );

  ELSIF _order_by = ANY('{rank,votes,voters_num}'::TEXT[]) THEN

    RETURN QUERY EXECUTE format(
      $query$

      WITH limited_set AS (
        SELECT witness_id, rank, votes, voters_num
        FROM hafbe_app.witness_votes_cache
        ORDER BY
          (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
          (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC
        OFFSET %L
        LIMIT %L
      )

      SELECT
        hav.name::TEXT, ls.rank, cw.url,
        ls.votes,
        COALESCE(todays_votes.votes_daily_change, 0)::BIGINT AS votes_daily_change,
        ls.voters_num,
        COALESCE(todays_votes.voters_num_daily_change, 0)::INT AS voters_num_daily_change,
        cw.price_feed, cw.bias,
        (NOW() - cw.feed_updated_at)::INTERVAL,
        cw.block_size, cw.signing_key, cw.version
      FROM limited_set ls
      JOIN hafbe_app.current_witnesses cw ON cw.witness_id = ls.witness_id
      LEFT JOIN LATERAL (
        SELECT wvcc.witness_id, wvcc.votes_daily_change, wvcc.voters_num_daily_change
        FROM hafbe_app.witness_votes_change_cache wvcc
        WHERE wvcc.witness_id = ls.witness_id
        GROUP BY wvcc.witness_id
      ) todays_votes ON TRUE
      JOIN (
        SELECT name, id
        FROM hive.accounts_view
      ) hav ON hav.id = ls.witness_id
      ORDER BY
        (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
        (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC

      $query$,
      _order_is, _order_by, _order_is, _order_by, _offset, _limit,
      _order_is, _order_by, _order_is, _order_by
    );

  ELSIF _order_by = ANY('{votes_daily_change,voters_num_daily_change}') THEN

    RETURN QUERY EXECUTE format(
      $query$

      WITH limited_set AS (
        SELECT witness_id, votes_daily_change, voters_num_daily_change
        FROM (
          SELECT witness_id, votes_daily_change, voters_num_daily_change
          FROM hafbe_app.witness_votes_change_cache wvcc
          GROUP BY witness_id
        ) wvcc
        ORDER BY
          (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
          (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC
        OFFSET %L
        LIMIT %L        
      )

      SELECT
        hav.name::TEXT, all_votes.rank, cw.url,
        all_votes.votes::NUMERIC,
        ls.votes_daily_change,
        all_votes.voters_num::INT,
        ls.voters_num_daily_change,
        cw.price_feed, cw.bias,
        (NOW() - cw.feed_updated_at)::INTERVAL,
        cw.block_size, cw.signing_key, cw.version
      FROM limited_set ls
      JOIN hafbe_app.current_witnesses cw ON cw.witness_id = ls.witness_id
      LEFT JOIN (
        SELECT witness_id, rank, votes, voters_num
        FROM hafbe_app.witness_votes_cache
      ) all_votes ON all_votes.witness_id = ls.witness_id
      JOIN hive.accounts_view hav ON hav.id = ls.witness_id
      ORDER BY
        (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
        (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC

      $query$,
      _order_is, _order_by, _order_is, _order_by, _offset, _limit,
      _order_is, _order_by, _order_is, _order_by
    );

  ELSE

    RETURN QUERY EXECUTE format(
      $query$
      
      WITH limited_set AS (
        SELECT
          witness_id, url, price_feed, bias,
          (NOW() - feed_updated_at)::INTERVAL AS feed_age,
          block_size, signing_key, version
        FROM hafbe_app.current_witnesses
        WHERE %I IS NOT NULL
        ORDER BY
          (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
          (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC
        OFFSET %L
        LIMIT %L        
      )

      SELECT
        hav.name::TEXT, rank::INT, url,
        COALESCE(all_votes.votes, 0)::NUMERIC,
        COALESCE(todays_votes.votes_daily_change, 0)::BIGINT,
        COALESCE(all_votes.voters_num, 0)::INT,
        COALESCE(todays_votes.voters_num_daily_change, 0)::INT,
        price_feed, bias, feed_age, block_size, signing_key, version
      FROM limited_set ls
      LEFT JOIN (
        SELECT witness_id, rank, votes, voters_num
        FROM hafbe_app.witness_votes_cache
      ) all_votes ON all_votes.witness_id = ls.witness_id
      LEFT JOIN LATERAL (
        SELECT wvcc.witness_id, wvcc.votes_daily_change, wvcc.voters_num_daily_change
        FROM hafbe_app.witness_votes_change_cache wvcc
        WHERE wvcc.witness_id = ls.witness_id
        GROUP BY wvcc.witness_id
      ) todays_votes ON TRUE
      JOIN hive.accounts_view hav ON hav.id = ls.witness_id
      ORDER BY
        (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
        (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC

      $query$,
      _order_by, _order_is, _order_by, _order_is, _order_by, _offset, _limit,
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

CREATE FUNCTION hafbe_backend.get_set_of_witnesses_in_hp(_limit INT, _offset INT, _order_by TEXT, _order_is TEXT)
RETURNS SETOF hafbe_types.witnesses_in_hp
AS
$function$
BEGIN
  RETURN QUERY SELECT
    witness, rank, url, conv.votes, conv.votes_daily_change, voters_num, voters_num_daily_change,
    price_feed, bias, feed_age, block_size, signing_key, version
  FROM hafbe_backend.get_set_of_witnesses_in_vests(_limit, _offset, _order_by, _order_is)
  JOIN LATERAL (
    SELECT arr_hp[1] AS votes, arr_hp[2] AS votes_daily_change
    FROM (
      SELECT array_agg(hp) AS arr_hp
      FROM hafbe_backend.vests_to_hive_power(votes, votes_daily_change) hp
    ) to_arr
  ) conv ON TRUE;
END
$function$
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
;

CREATE FUNCTION hafbe_backend.vests_to_hive_power(VARIADIC vests_value NUMERIC[])
RETURNS SETOF FLOAT
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN QUERY SELECT (
    unnest(vests_value)
      *
    (SELECT value FROM hafbe_app.dynamic_global_properties_cache WHERE property = 'vesting_fund')
      *
    10 ^ (SELECT precision FROM hafbe_app.dynamic_global_properties_cache WHERE property = 'vesting_fund')
  ) / (
    (SELECT value FROM hafbe_app.dynamic_global_properties_cache WHERE property = 'vesting_shares')
      *
    10 ^ (SELECT precision FROM hafbe_app.dynamic_global_properties_cache WHERE property = 'vesting_shares')
  )::FLOAT;
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

CREATE FUNCTION hafbe_backend.get_account_resource_credits(_account TEXT)
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
          -d '{"jsonrpc": "2.0", "method": "rc_api.find_rc_accounts", "params": {"accounts":["%s"]}, "id": null}'
        """ % _account
      ], shell=True).decode('utf-8')
    )['result']['rc_accounts'][0]
  )
$$
;