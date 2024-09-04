SET ROLE hafbe_owner;

DROP FUNCTION IF EXISTS hafbe_backend.get_witness_voters;
CREATE OR REPLACE FUNCTION hafbe_backend.get_witness_voters(
    "account-name" TEXT,
    "sort" hafbe_types.order_by_votes,
    "direction" hafbe_types.sort_direction,
    "result-limit" INT
)
RETURNS SETOF hafbe_types.witness_voter 
-- openapi-generated-code-end
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_witness_id INT = hafbe_backend.get_account_id("account-name");
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
  ls.vests::TEXT,
  (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), ls.vests))::BIGINT,
  ls.account_vests::TEXT,
  (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), ls.account_vests))::BIGINT,
  ls.proxied_vests::TEXT,
  (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), ls.proxied_vests))::BIGINT,
  ls.timestamp
  FROM limited_set_order ls
  ORDER BY
    (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
    (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC
  ;

  $query$,
  _witness_id, "direction", "sort", "direction", "sort", "result-limit",
  "direction", "sort", "direction", "sort"
) res;

END
$$;

DROP FUNCTION IF EXISTS hafbe_backend.get_witness_votes_history;
CREATE OR REPLACE FUNCTION hafbe_backend.get_witness_votes_history(
    "account-name" TEXT,
    "sort" hafbe_types.order_by_votes,
    "direction" hafbe_types.sort_direction,
    "result-limit" INT,
    "start-date" TIMESTAMP,
    "end-date" TIMESTAMP 
)
RETURNS SETOF hafbe_types.witness_votes_history_record 
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_witness_id INT = hafbe_backend.get_account_id("account-name");
BEGIN

IF "start-date" IS NULL THEN 
  "start-date" := '1970-01-01T00:00:00'::TIMESTAMP;
END IF;

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
    (wvh.account_vests + wvh.proxied_vests )::TEXT AS vests, 
    (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), (wvh.account_vests + wvh.proxied_vests) ))::BIGINT AS vests_hive_power,
    wvh.account_vests::TEXT AS account_vests, 
    (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), wvh.account_vests))::BIGINT AS account_hive_power,
    wvh.proxied_vests::TEXT AS proxied_vests,
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
  _witness_id,"start-date", "end-date", "result-limit", "direction", "sort", "direction", "sort"
) res;
END
$$;

DROP FUNCTION IF EXISTS hafbe_backend.get_witnesses;
CREATE OR REPLACE FUNCTION hafbe_backend.get_witnesses(
    "result-limit" INT,
    "offset" INT,
    "sort" hafbe_types.order_by_witness,
    "direction" hafbe_types.sort_direction
)
RETURNS SETOF hafbe_types.witness 
LANGUAGE 'plpgsql'
STABLE
AS
$$
BEGIN
  RETURN QUERY EXECUTE format(
    $query$

    WITH limited_set AS 
    (
      SELECT
        cw.witness_id, 
        (SELECT av.name FROM hive.accounts_view av WHERE av.id = cw.witness_id)::TEXT AS witness,
        COALESCE(cw.url, '') AS url,
        COALESCE(cw.price_feed, '0.000'::NUMERIC) AS price_feed,
        cw.bias,
        COALESCE(cw.feed_updated_at, '1970-01-01 00:00:00'::TIMESTAMP) AS feed_updated_at,
        cw.block_size, 
        COALESCE(cw.signing_key, '') AS signing_key, 
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
        cw.hbd_interest_rate,
        cw.last_created_block_num,
        cw.account_creation_fee 
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
    (
      SELECT bv.num AS block_num FROM hive.blocks_view bv ORDER BY bv.num DESC LIMIT 1
    )
    SELECT
      ls.witness, 
      ls.rank, 
      ls.url,
      ls.votes::TEXT,
      (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), ls.votes))::BIGINT, 
      ls.votes_daily_change::TEXT,
      (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), ls.votes_daily_change))::BIGINT, 
      ls.voters_num,
      ls.voters_num_daily_change,
      ls.price_feed, 
      ls.bias, 
      ls.feed_updated_at,
      ls.block_size, 
      ls.signing_key, 
      ls.version,
      ls.missed_blocks,
      ls.hbd_interest_rate,
      ls.last_created_block_num,
      ls.account_creation_fee
    FROM limited_set_order ls
    ORDER BY
      (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
      (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC

    $query$,
    "direction", "sort", "direction", "sort", "offset","result-limit",
    "direction", "sort", "direction", "sort"
  );

END
$$;


DROP FUNCTION IF EXISTS hafbe_backend.get_witness;
CREATE OR REPLACE FUNCTION hafbe_backend.get_witness(
    "account-name" TEXT
)
RETURNS hafbe_types.witness 
LANGUAGE 'plpgsql'
STABLE
AS
$$
BEGIN
  RETURN (
    WITH limited_set AS (
    SELECT
      cw.witness_id, av.name::TEXT AS witness,
      COALESCE(cw.url, '') AS url,
      COALESCE(cw.price_feed, '0.000'::NUMERIC) AS price_feed,
      cw.bias,
      COALESCE(cw.feed_updated_at, '1970-01-01 00:00:00'::TIMESTAMP) AS feed_updated_at,
      cw.block_size, 
      COALESCE(cw.signing_key, '') AS signing_key, 
      cw.version,
      COALESCE(
      (
          SELECT count(*) as missed
          FROM hive.account_operations_view aov
          WHERE aov.op_type_id = 86 AND aov.account_id = cw.witness_id
      )::INT
      ,0) AS missed_blocks,
      cw.hbd_interest_rate,
      cw.last_created_block_num,
      cw.account_creation_fee
    FROM hive.accounts_view av
    JOIN hafbe_app.current_witnesses cw ON av.id = cw.witness_id
    WHERE av.name = "account-name"
    ),
    get_block_num AS MATERIALIZED
    (SELECT bv.num AS block_num FROM hive.blocks_view bv ORDER BY bv.num DESC LIMIT 1)

    SELECT ROW(
    ls.witness, 
    all_votes.rank, 
    ls.url,
    COALESCE(all_votes.votes::TEXT, '0'),
    (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), COALESCE(all_votes.votes, 0)))::BIGINT, 
    COALESCE(wvcc.votes_daily_change::TEXT, '0'),
    (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), COALESCE(wvcc.votes_daily_change, 0)))::BIGINT, 
    COALESCE(all_votes.voters_num, 0),
    COALESCE(wvcc.voters_num_daily_change, 0),
    ls.price_feed, 
    ls.bias, 
    ls.feed_updated_at,
    ls.block_size, 
    ls.signing_key, 
    ls.version,
    ls.missed_blocks, 
    ls.hbd_interest_rate,
    ls.last_created_block_num,
    ls.account_creation_fee
    )
    FROM limited_set ls
    LEFT JOIN hafbe_app.witness_votes_cache all_votes ON all_votes.witness_id = ls.witness_id 
    LEFT JOIN hafbe_app.witness_votes_change_cache wvcc ON wvcc.witness_id = ls.witness_id
  );

END
$$;


RESET ROLE;
