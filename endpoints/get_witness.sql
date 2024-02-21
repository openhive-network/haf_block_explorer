SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_witness_voters_num(_witness TEXT)
RETURNS INT
LANGUAGE 'plpgsql' STABLE
AS
$$
DECLARE
  _witness_id INT = hafbe_backend.get_account_id(_witness);
BEGIN
  RETURN COUNT(1) FROM hafbe_app.current_witness_votes WHERE witness_id = _witness_id;
END
$$;

-- Witness page endpoint
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_witness_voters(
    _witness TEXT,
    _order_by hafbe_types.order_by_votes = 'vests', -- noqa: LT01, CP05
    _order_is hafbe_types.order_is = 'desc', -- noqa: LT01, CP05
    _limit INT = 2147483647
)
RETURNS SETOF hafbe_types.witness_voters -- noqa: LT01, CP05
LANGUAGE 'plpgsql'
STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
AS
$$
DECLARE
_witness_id INT = hafbe_backend.get_account_id(_witness);
BEGIN
RETURN QUERY EXECUTE format(
  $query$

  WITH limited_set AS (
    SELECT 
      (SELECT av.name FROM hive.accounts_view av WHERE av.id = wvsc.voter_id)::TEXT AS voter,
      wvsc.voter_id, wvsc.vests, wvsc.account_vests, wvsc.proxied_vests, wvsc.timestamp
    FROM hafbe_app.witness_voters_stats_cache wvsc
    WHERE witness_id = %L   
  ),
  limited_set_order AS MATERIALIZED (
    SELECT * FROM limited_set
    ORDER BY
      (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
      (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC  
    LIMIT %L
  ),
  get_block_num AS MATERIALIZED
  (SELECT bv.num AS block_num FROM hive.blocks_view bv ORDER BY bv.num DESC LIMIT 1)

  SELECT ls.voter, 
  ls.vests,
  (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), ls.vests))::BIGINT,
  ls.account_vests,
  (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), ls.account_vests))::BIGINT,
  ls.proxied_vests,
  (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), ls.proxied_vests))::BIGINT,
  ls.timestamp
  FROM limited_set_order ls
  ORDER BY
    (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
    (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC
  ;

  $query$,
  _witness_id, _order_is, _order_by, _order_is, _order_by, _limit,
  _order_is, _order_by, _order_is, _order_by
) res;

END
$$;

-- Witness page endpoint
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_witness_votes_history(
    _witness TEXT,
    _order_by hafbe_types.order_by_votes = 'timestamp', -- noqa: LT01, CP05
    _order_is hafbe_types.order_is = 'desc', -- noqa: LT01, CP05
    _limit INT = 100,
    _from_time TIMESTAMP = '1970-01-01T00:00:00'::TIMESTAMP,
    _to_time TIMESTAMP = NOW()
)
RETURNS SETOF hafbe_types.witness_votes_history -- noqa: LT01, CP05
LANGUAGE 'plpgsql'
STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
AS
$$
DECLARE
_witness_id INT = hafbe_backend.get_account_id(_witness);
BEGIN
RETURN QUERY EXECUTE format(
  $query$

  WITH select_range AS MATERIALIZED (
    SELECT 
      (SELECT av.name FROM hive.accounts_view av WHERE av.id = wvh.voter_id)::TEXT AS voter,
      * 
    FROM hafbe_app.witness_votes_history_cache wvh
    WHERE wvh.witness_id = %L
    AND wvh.timestamp BETWEEN  %L AND  %L
    ORDER BY wvh.timestamp DESC
    LIMIT %L
  ),
  get_block_num AS MATERIALIZED
    (SELECT bv.num AS block_num FROM hive.blocks_view bv ORDER BY bv.num DESC LIMIT 1),
  select_votes_history AS (
  SELECT
    wvh.voter, wvh.approve, 
    (wvh.account_vests + wvh.proxied_vests ) AS vests, 
    (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), (wvh.account_vests + wvh.proxied_vests) ))::BIGINT AS vests_hive_power,
    wvh.account_vests AS account_vests, 
    (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), wvh.account_vests))::BIGINT AS account_hive_power,
    wvh.proxied_vests AS proxied_vests,
    (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), wvh.proxied_vests))::BIGINT AS proxied_hive_power,
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
$$;

-- Witness page endpoint
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_witnesses(
    _limit INT = 100,
    _offset INT = 0,
    _order_by hafbe_types.order_by_witness = 'votes', -- noqa: LT01, CP05
    _order_is hafbe_types.order_is = 'desc' -- noqa: LT01, CP05
)
RETURNS SETOF hafbe_types.witness_setof -- noqa: LT01, CP05
LANGUAGE 'plpgsql'
STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
AS
$$
BEGIN
RETURN QUERY EXECUTE format(
  $query$

  WITH limited_set AS (
    SELECT
      cw.witness_id, 
      (SELECT av.name FROM hive.accounts_view av WHERE av.id = cw.witness_id)::TEXT AS witness,
      cw.url,
      cw.price_feed,
      cw.bias,
      (NOW() - cw.feed_updated_at)::INTERVAL AS feed_age,
      cw.block_size, 
      cw.signing_key, 
      cw.version, 
      b.rank, 
      COALESCE(b.votes,0) AS votes, 
      COALESCE(b.voters_num,0) AS voters_num, 
      COALESCE(c.votes_daily_change, 0) AS votes_daily_change, 
      COALESCE(c.voters_num_daily_change,0) AS voters_num_daily_change,
      COALESCE(
      (
        SELECT count(*) as missed
        FROM hive.account_operations_view aov 
        WHERE aov.op_type_id = 86 AND aov.account_id = cw.witness_id
      )::INT
      ,0) AS missed_blocks,
      COALESCE(cw.hbd_interest_rate,0) AS hbd_interest_rate
    FROM hafbe_app.current_witnesses cw
    LEFT JOIN hafbe_app.witness_votes_cache b ON b.witness_id = cw.witness_id
    LEFT JOIN hafbe_app.witness_votes_change_cache c ON c.witness_id = cw.witness_id
  ),
  limited_set_order AS MATERIALIZED (
    SELECT * FROM limited_set
    ORDER BY
      (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
      (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC
    OFFSET %L
    LIMIT %L
  ),
get_block_num AS MATERIALIZED
(SELECT bv.num AS block_num FROM hive.blocks_view bv ORDER BY bv.num DESC LIMIT 1)

  SELECT
    ls.witness, 
    ls.rank, 
    ls.url,
    ls.votes,
    (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), ls.votes))::BIGINT, 
    ls.votes_daily_change,
    (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), ls.votes_daily_change))::BIGINT, 
    ls.voters_num,
    ls.voters_num_daily_change,
    ls.price_feed, 
    ls.bias, 
    ls.feed_age, 
    ls.block_size, 
    ls.signing_key, 
    ls.version,
    ls.missed_blocks,
    ls.hbd_interest_rate
  FROM limited_set_order ls
  ORDER BY
    (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
    (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC

  $query$,
  _order_is,_order_by, _order_is,_order_by, _offset,_limit,
  _order_is, _order_by, _order_is,_order_by
)
;

END
$$;

-- Witness page endpoint
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_witness(_account TEXT)
RETURNS hafbe_types.witness_setof -- noqa: LT01, CP05
LANGUAGE 'plpgsql'
STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
AS
$$
BEGIN
RETURN (
WITH limited_set AS (
  SELECT
    cw.witness_id, av.name::TEXT AS witness,
    cw.url, cw.price_feed, cw.bias,
    (NOW() - cw.feed_updated_at)::INTERVAL AS feed_age,
    cw.block_size, cw.signing_key, cw.version,
    COALESCE(
      (
        SELECT count(*) as missed
        FROM hive.account_operations_view aov 
        WHERE aov.op_type_id = 86 AND aov.account_id = cw.witness_id
      )::INT
    ,0) AS missed_blocks,
    COALESCE(cw.hbd_interest_rate, 0) AS hbd_interest_rate
  FROM hive.accounts_view av
  JOIN hafbe_app.current_witnesses cw ON av.id = cw.witness_id
  WHERE av.name = _account
),
get_block_num AS MATERIALIZED
(SELECT bv.num AS block_num FROM hive.blocks_view bv ORDER BY bv.num DESC LIMIT 1)

SELECT ROW(
  ls.witness, 
  all_votes.rank, 
  ls.url,
  COALESCE(all_votes.votes, 0),
  (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), COALESCE(all_votes.votes, 0)))::BIGINT, 
  COALESCE(wvcc.votes_daily_change, 0),
  (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), COALESCE(wvcc.votes_daily_change, 0)))::BIGINT, 
  COALESCE(all_votes.voters_num, 0),
  COALESCE(wvcc.voters_num_daily_change, 0),
  ls.price_feed, 
  ls.bias, 
  ls.feed_age, 
  ls.block_size, 
  ls.signing_key, 
  ls.version,
  ls.missed_blocks, 
  ls.hbd_interest_rate
  )
FROM limited_set ls
LEFT JOIN hafbe_app.witness_votes_cache all_votes ON all_votes.witness_id = ls.witness_id 
LEFT JOIN hafbe_app.witness_votes_change_cache wvcc ON wvcc.witness_id = ls.witness_id

);

END
$$;

RESET ROLE;
