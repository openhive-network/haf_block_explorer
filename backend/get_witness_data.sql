/*
witness voters
*/

CREATE OR REPLACE FUNCTION hafbe_backend.get_witness_voters_num(_witness_id INT)
RETURNS INT
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN COUNT(1) FROM hafbe_app.current_witness_votes WHERE witness_id = _witness_id;
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_backend.get_set_of_witness_voters_in_vests(_witness_id INT, _limit INT, _offset INT, _order_by TEXT, _order_is TEXT)
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

CREATE OR REPLACE FUNCTION hafbe_backend.get_set_of_witness_voters_in_hp(_witness_id INT, _limit INT, _offset INT, _order_by TEXT, _order_is TEXT)
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

CREATE OR REPLACE FUNCTION hafbe_backend.get_set_of_witness_voters_daily_change_in_vests(_witness_id INT, _limit INT, _offset INT, _order_by TEXT, _order_is TEXT)
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

CREATE OR REPLACE FUNCTION hafbe_backend.get_set_of_witness_voters_daily_change_in_hp(_witness_id INT, _limit INT, _offset INT, _order_by TEXT, _order_is TEXT)
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


CREATE OR REPLACE FUNCTION hafbe_backend.get_set_of_witnesses_in_vests(_limit INT, _offset INT, _order_by TEXT, _order_is TEXT)
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
COST 10000
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
;

CREATE OR REPLACE FUNCTION hafbe_backend.get_set_of_witnesses_in_hp(_limit INT, _offset INT, _order_by TEXT, _order_is TEXT)
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
