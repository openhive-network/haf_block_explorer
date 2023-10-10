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

CREATE OR REPLACE FUNCTION hafbe_backend.get_set_of_witness_voters(_witness_id INT, _order_by TEXT, _order_is TEXT)
RETURNS SETOF hafbe_types.witness_voters
LANGUAGE 'plpgsql'
STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
SET cursor_tuple_fraction='0.9'
AS
$$
BEGIN
  IF _order_by = 'voter' THEN

    RETURN QUERY EXECUTE format(
      $query$

      WITH limited_set AS (
        SELECT 
          cwv.voter_id,
          hav.name::TEXT AS voter,
          (SELECT num AS block_num FROM hive.blocks_view ORDER BY num DESC LIMIT 1) AS current_block_num
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
      )

      SELECT 
        ls.voter,
        (vsv.vests/1000000)::BIGINT,
        ((SELECT hive.get_vesting_balance(ls.current_block_num, vsv.vests))/1000000)::BIGINT,
        (vsv.account_vests/1000000)::BIGINT,
        ((SELECT hive.get_vesting_balance(ls.current_block_num, vsv.account_vests))/1000000)::BIGINT,
        (vsv.proxied_vests/1000000)::BIGINT, 
        ((SELECT hive.get_vesting_balance(ls.current_block_num, vsv.proxied_vests))/1000000)::BIGINT,
        vsv.timestamp
      FROM limited_set ls
      JOIN 
      JOIN (
        SELECT voter_id, vests::BIGINT, account_vests::BIGINT, proxied_vests::BIGINT, timestamp
        --hafbe_app.witness_voters_stats_cache
        FROM hafbe_app.witness_voters_stats_cache
        WHERE witness_id = %L
      ) vsv ON vsv.voter_id = ls.voter_id
      ORDER BY
        (CASE WHEN %L = 'desc' THEN ls.voter ELSE NULL END) DESC,
        (CASE WHEN %L = 'asc' THEN ls.voter ELSE NULL END) ASC
      ;

      $query$,
      _witness_id, _order_is, _order_is,
      _witness_id, _order_is, _order_is
    ) res;

  ELSE

    RETURN QUERY EXECUTE format(
      $query$

      WITH limited_set AS (
        SELECT voter_id, vests::BIGINT, account_vests::BIGINT, proxied_vests::BIGINT, timestamp, (SELECT num AS block_num FROM hive.blocks_view ORDER BY num DESC LIMIT 1) AS current_block_num
        --hafbe_app.witness_voters_stats_cache
        FROM hafbe_app.witness_voters_stats_cache
        WHERE witness_id = %L
        ORDER BY
          (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
          (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC     
      )

      SELECT hav.name::TEXT, 
      (ls.vests/1000000)::BIGINT,
      ((SELECT hive.get_vesting_balance(ls.current_block_num, ls.vests))/1000000)::BIGINT,
      (ls.account_vests/1000000)::BIGINT,
      ((SELECT hive.get_vesting_balance(ls.current_block_num, ls.account_vests))/1000000)::BIGINT,
      (ls.proxied_vests/1000000)::BIGINT,
      ((SELECT hive.get_vesting_balance(ls.current_block_num, ls.proxied_vests))/1000000)::BIGINT,
      ls.timestamp
      FROM limited_set ls
      JOIN hive.accounts_view hav ON hav.id = ls.voter_id
      ORDER BY
        (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
        (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC
      ;

      $query$,
      _witness_id, _order_is, _order_by, _order_is, _order_by,
      _order_is, _order_by, _order_is, _order_by
    ) res;

  END IF;
END
$$
;


CREATE OR REPLACE FUNCTION hafbe_backend.get_set_of_witness_votes_history(_witness_id INT, _order_by TEXT, _order_is TEXT, _limit INT, _from_time TIMESTAMP, _to_time TIMESTAMP)
RETURNS SETOF hafbe_types.witness_votes_history
LANGUAGE 'plpgsql'
STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
SET cursor_tuple_fraction='0.9'
AS
$$
BEGIN
    RETURN QUERY EXECUTE format(
      $query$

  WITH select_range AS MATERIALIZED (
    SELECT a.name::TEXT AS voter, * FROM hafbe_app.witness_votes_history_cache wvh
    JOIN hive.accounts_view a ON a.id = wvh.voter_id
    WHERE wvh.witness_id = %L
    AND wvh.timestamp BETWEEN  %L AND  %L
    ORDER BY wvh.timestamp DESC
        LIMIT %L
  ),
  get_block_num AS MATERIALIZED
    (SELECT num AS block_num FROM hive.blocks_view ORDER BY num DESC LIMIT 1),
  select_votes_history AS (
      SELECT
    wvh.voter, wvh.approve, 
    (wvh.account_vests + wvh.proxied_vests ) AS vests, 
    (SELECT hive.get_vesting_balance((SELECT * FROM get_block_num), (wvh.account_vests + wvh.proxied_vests) ))::BIGINT AS vests_hive_power,
    wvh.account_vests AS account_vests, 
    (SELECT hive.get_vesting_balance((SELECT * FROM get_block_num), wvh.account_vests))::BIGINT AS account_hive_power,
    wvh.proxied_vests AS proxied_vests,
    (SELECT hive.get_vesting_balance((SELECT * FROM get_block_num), wvh.proxied_vests))::BIGINT AS proxied_hive_power,
    wvh.timestamp AS timestamp
  FROM select_range wvh
  )
  SELECT * FROM select_votes_history
      ORDER BY
    (CASE WHEN %L = 'desc' THEN  %I ELSE NULL END) DESC,
        (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC
      ;
      $query$,
  _witness_id,_from_time, _to_time, _limit, _order_is, _order_by, _order_is, _order_by
    ) res;
END
$$
;

/*
witnesses
*/

CREATE OR REPLACE FUNCTION hafbe_backend.get_set_of_witnesses(_limit INT, _offset INT, _order_by TEXT, _order_is TEXT)
RETURNS SETOF hafbe_types.witness_setof
LANGUAGE 'plpgsql'
STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
SET cursor_tuple_fraction='0.9'
AS
$$
DECLARE
  __today DATE := (SELECT hafbe_backend.get_todays_date());
BEGIN
  IF _order_by = 'witness' THEN

    RETURN QUERY EXECUTE format(
      $query$

      WITH limited_set AS (
        SELECT
          cw.witness_id, hav.name::TEXT AS witness,
          cw.url, cw.price_feed, cw.bias,
          (NOW() - cw.feed_updated_at)::INTERVAL AS feed_age,
          cw.block_size, cw.signing_key, cw.version, (SELECT num AS block_num FROM hive.blocks_view ORDER BY num DESC LIMIT 1) AS current_block_num
        FROM hive.accounts_view hav
        JOIN hafbe_app.current_witnesses cw ON hav.id = cw.witness_id
        ORDER BY
          (CASE WHEN %L = 'desc' THEN hav.name ELSE NULL END) DESC,
          (CASE WHEN %L = 'asc' THEN hav.name ELSE NULL END) ASC
        OFFSET %L
        LIMIT %L
      )

      SELECT
        ls.witness, 
        all_votes.rank::INT, 
        ls.url,
        (COALESCE(all_votes.votes, 0)/1000000)::BIGINT,
        ((SELECT hive.get_vesting_balance(ls.current_block_num, COALESCE(all_votes.votes, 0)::BIGINT))/1000000)::BIGINT, 
        (COALESCE(todays_votes.votes_daily_change, 0)/1000000)::BIGINT,
        ((SELECT hive.get_vesting_balance(ls.current_block_num, COALESCE(todays_votes.votes_daily_change, 0)::BIGINT))/1000000)::BIGINT, 
        COALESCE(all_votes.voters_num, 0)::INT,
        COALESCE(todays_votes.voters_num_daily_change, 0)::INT,
        ls.price_feed, 
        ls.bias, 
        ls.feed_age, 
        ls.block_size, 
        ls.signing_key, 
        ls.version
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
        SELECT witness_id, rank, votes, voters_num, (SELECT num AS block_num FROM hive.blocks_view ORDER BY num DESC LIMIT 1) AS current_block_num
        FROM hafbe_app.witness_votes_cache
        ORDER BY
          (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
          (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC
        OFFSET %L
        LIMIT %L
      )

      SELECT
        hav.name::TEXT, 
        ls.rank::INT, 
        cw.url,
        (ls.votes/1000000)::BIGINT,
        ((SELECT hive.get_vesting_balance(ls.current_block_num, ls.votes::BIGINT))/1000000)::BIGINT, 
        (COALESCE(todays_votes.votes_daily_change, 0)/1000000)::BIGINT AS votes_daily_change,
        ((SELECT hive.get_vesting_balance(ls.current_block_num, COALESCE(todays_votes.votes_daily_change, 0)::BIGINT))/1000000)::BIGINT, 
        ls.voters_num::INT,
        COALESCE(todays_votes.voters_num_daily_change, 0)::INT AS voters_num_daily_change,
        cw.price_feed, 
        cw.bias,
        (NOW() - cw.feed_updated_at)::INTERVAL,
        cw.block_size, 
        cw.signing_key, 
        cw.version
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
        SELECT witness_id, votes_daily_change, voters_num_daily_change, (SELECT num AS block_num FROM hive.blocks_view ORDER BY num DESC LIMIT 1) AS current_block_num
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
        hav.name::TEXT, 
        all_votes.rank::INT, 
        w.url,
        (all_votes.votes/1000000)::BIGINT,
        ((SELECT hive.get_vesting_balance(ls.current_block_num, all_votes.votes::BIGINT))/1000000)::BIGINT, 
        (ls.votes_daily_change/1000000)::BIGINT,
        ((SELECT hive.get_vesting_balance(ls.current_block_num, ls.votes_daily_change))/1000000)::BIGINT,
        all_votes.voters_num::INT,
        ls.voters_num_daily_change,
        cw.price_feed, 
        cw.bias,
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
          block_size, signing_key, version, (SELECT num AS block_num FROM hive.blocks_view ORDER BY num DESC LIMIT 1) AS current_block_num
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
        (COALESCE(all_votes.votes, 0)/1000000)::BIGINT,
        ((SELECT hive.get_vesting_balance(ls.current_block_num, COALESCE(all_votes.votes, 0)::BIGINT))/1000000)::BIGINT, 
        (COALESCE(todays_votes.votes_daily_change, 0)/1000000)::BIGINT,
        ((SELECT hive.get_vesting_balance(ls.current_block_num, COALESCE(todays_votes.votes_daily_change, 0)::BIGINT))/1000000)::BIGINT, 
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
$$
;

CREATE OR REPLACE FUNCTION hafbe_backend.get_setof_witness(_account TEXT)
RETURNS SETOF hafbe_types.witness_setof
LANGUAGE 'plpgsql'
STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
SET cursor_tuple_fraction='0.9'
AS
$$
BEGIN
RETURN QUERY
WITH limited_set AS (
  SELECT
    cw.witness_id, hav.name::TEXT AS witness,
    cw.url, cw.price_feed, cw.bias,
    (NOW() - cw.feed_updated_at)::INTERVAL AS feed_age,
    cw.block_size, cw.signing_key, cw.version,
    (SELECT num AS block_num FROM hive.blocks_view ORDER BY num DESC LIMIT 1) AS current_block_num
  FROM hive.accounts_view hav
  JOIN hafbe_app.current_witnesses cw ON hav.id = cw.witness_id
  WHERE hav.name = _account
)

SELECT
  ls.witness, 
  all_votes.rank::INT, 
  ls.url,
  (COALESCE(all_votes.votes, 0)/1000000)::BIGINT,
  ((SELECT hive.get_vesting_balance(ls.current_block_num, COALESCE(all_votes.votes, 0)::BIGINT))/1000000)::BIGINT, 
  (COALESCE(todays_votes.votes_daily_change, 0)/1000000)::BIGINT,
  ((SELECT hive.get_vesting_balance(ls.current_block_num, COALESCE(todays_votes.votes_daily_change, 0)::BIGINT))/1000000)::BIGINT, 
  COALESCE(all_votes.voters_num, 0)::INT,
  COALESCE(todays_votes.voters_num_daily_change, 0)::INT,
  ls.price_feed, 
  ls.bias, 
  ls.feed_age, 
  ls.block_size, 
  ls.signing_key, 
  ls.version
FROM limited_set ls
LEFT JOIN hafbe_app.witness_votes_cache all_votes ON all_votes.witness_id = ls.witness_id 
LEFT JOIN LATERAL (
  SELECT wvcc.witness_id, wvcc.votes_daily_change, wvcc.voters_num_daily_change
  FROM hafbe_app.witness_votes_change_cache wvcc
  WHERE wvcc.witness_id = ls.witness_id
    GROUP BY wvcc.witness_id
) todays_votes ON TRUE;
END
$$
;