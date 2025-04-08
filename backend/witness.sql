SET ROLE hafbe_owner;

DROP FUNCTION IF EXISTS hafbe_backend.get_witness_voters;
CREATE OR REPLACE FUNCTION hafbe_backend.get_witness_voters(
    "account_id" INT,
    "page" INT,
    "page-size" INT,
    "sort" hafbe_types.order_by_votes,
    "direction" hafbe_types.sort_direction
)
RETURNS SETOF hafbe_types.witness_voter 
-- openapi-generated-code-end
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _offset INT := ((("page" - 1) * "page-size"));
BEGIN
  RETURN QUERY EXECUTE format(
    $query$

    WITH limited_set AS (
      SELECT 
        (
          SELECT av.name 
          FROM hive.accounts_view av 
          WHERE av.id = wvsc.voter_id
        )::TEXT AS voter,
        wvsc.voter_id, 
        wvsc.vests, 
        wvsc.account_vests,
        wvsc.proxied_vests, 
        wvsc.timestamp
      FROM hafbe_app.witness_voters_stats_cache wvsc
      WHERE witness_id = %L   
    ),
    limited_set_order AS MATERIALIZED (
      SELECT * FROM limited_set
      ORDER BY
        (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
        (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC,
        (CASE WHEN %L = 'desc' THEN voter_id ELSE NULL END) DESC,
        (CASE WHEN %L = 'asc' THEN voter_id ELSE NULL END) ASC
      OFFSET %L  
      LIMIT %L
    )
    SELECT 
      ls.voter, 
      ls.vests::TEXT,
      ls.account_vests::TEXT,
      ls.proxied_vests::TEXT,
      ls.timestamp
    FROM limited_set_order ls
    ORDER BY
      (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
      (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC,
      (CASE WHEN %L = 'desc' THEN voter_id ELSE NULL END) DESC,
      (CASE WHEN %L = 'asc' THEN voter_id ELSE NULL END) ASC
    ;

    $query$,
    "account_id", "direction", "sort", "direction", "sort", "direction", "direction", _offset, "page-size",
    "direction", "sort", "direction", "sort", "direction", "direction"
  ) res;

END
$$;

DROP FUNCTION IF EXISTS hafbe_backend.get_witness_votes_history;
CREATE OR REPLACE FUNCTION hafbe_backend.get_witness_votes_history(
    "account-name" TEXT,
    "sort" hafbe_types.order_by_votes,
    "direction" hafbe_types.sort_direction,
    "result-limit" INT,
    "from-block" INT,
    "to-block" INT 
)
RETURNS SETOF hafbe_types.witness_votes_history_record 
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  __no_start_date BOOLEAN := ("from-block" IS NULL);
  __no_end_date BOOLEAN := ("to-block" IS NULL);
  _start_date TIMESTAMP;
  _end_date TIMESTAMP;
  _witness_id INT = hafbe_backend.get_account_id("account-name");
BEGIN

RETURN QUERY EXECUTE format(
  $query$

  WITH select_range AS MATERIALIZED (
    SELECT 
      (SELECT av.name FROM hive.accounts_view av WHERE av.id = voter_id)::TEXT AS voter,
      * 
    FROM hafbe_app.witness_votes_history_cache 
    WHERE witness_id = %L AND
      (%L OR timestamp >= %L) AND
	    (%L OR timestamp <= %L)
    ORDER BY
      (CASE WHEN %L = 'desc' THEN timestamp ELSE NULL END) DESC,
      (CASE WHEN %L = 'asc' THEN timestamp ELSE NULL END) ASC
    LIMIT %L
  ),
  select_votes_history AS (
  SELECT
    wvh.voter, wvh.voter_id, wvh.approve, 
    (wvh.account_vests + wvh.proxied_vests) AS vests, 
    wvh.account_vests AS account_vests, 
    wvh.proxied_vests AS proxied_vests,
    wvh.timestamp AS timestamp
  FROM select_range wvh
  )
  SELECT 
    voter,
    approve,
    vests::TEXT,
    account_vests::TEXT,
    proxied_vests::TEXT,
    timestamp
  FROM select_votes_history
  ORDER BY
    (CASE WHEN %L = 'desc' THEN  %I ELSE NULL END) DESC,
    (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC,
    (CASE WHEN %L = 'desc' THEN  voter_id ELSE NULL END) DESC,
    (CASE WHEN %L = 'asc' THEN voter_id ELSE NULL END) ASC
  ;
  $query$,
  _witness_id,
  __no_start_date, 
  (SELECT bv.created_at FROM hive.blocks_view bv WHERE bv.num = "from-block"),
  __no_end_date,
  (SELECT bv.created_at FROM hive.blocks_view bv WHERE bv.num = "to-block"), 
  "direction", 
  "direction", 
  "result-limit",
  "direction", 
  "sort", 
  "direction", 
  "sort",
  "direction", 
  "direction"

) res;
END
$$;

DROP FUNCTION IF EXISTS hafbe_backend.get_witnesses;
CREATE OR REPLACE FUNCTION hafbe_backend.get_witnesses(
    "page" INT,
    "page-size" INT,
    "sort" hafbe_types.order_by_witness,
    "direction" hafbe_types.sort_direction
)
RETURNS SETOF hafbe_types.witness 
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _offset INT := ((("page" - 1) * "page-size"));
BEGIN
  RETURN QUERY EXECUTE format(
    $query$

    WITH limited_set AS 
    (
      SELECT
        cw.witness_id, 
        (SELECT av.name FROM hive.accounts_view av where av.id = cw.witness_id)::TEXT AS witness,
        b.rank, 
        COALESCE(cw.url, '') AS url,
        COALESCE(cw.price_feed, '0.000'::NUMERIC) AS price_feed,
        COALESCE(cw.bias, 0) AS bias,
        COALESCE(cw.feed_updated_at, '1970-01-01 00:00:00'::TIMESTAMP) AS feed_updated_at,
        COALESCE(cw.block_size, 0) AS block_size,
        COALESCE(cw.signing_key, '') AS signing_key, 
        COALESCE(cw.version, '0.0.0') AS version,
        COALESCE(cw.missed_blocks, 0) AS missed_blocks,
        COALESCE(b.votes,0) AS votes, 
        COALESCE(b.voters_num,0) AS voters_num, 
        COALESCE(c.votes_daily_change, 0) AS votes_daily_change, 
        COALESCE(c.voters_num_daily_change,0) AS voters_num_daily_change,
        COALESCE(cw.hbd_interest_rate,0) AS hbd_interest_rate,
        COALESCE(cw.last_created_block_num,0) AS last_created_block_num,
        COALESCE(cw.account_creation_fee,0) AS account_creation_fee
      FROM hafbe_app.current_witnesses cw
 --   join couses significant slowdown
 --   JOIN hive.accounts_view av ON av.id = cw.witness_id
      LEFT JOIN hafbe_app.witness_votes_cache b ON b.witness_id = cw.witness_id
      LEFT JOIN hafbe_app.witness_votes_change_cache c ON c.witness_id = cw.witness_id
    ),
    limited_set_order AS MATERIALIZED (
      SELECT * FROM limited_set
      ORDER BY
        (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
        (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC,
        (CASE WHEN %L = 'desc' THEN witness_id ELSE NULL END) DESC,
        (CASE WHEN %L = 'asc' THEN witness_id ELSE NULL END) ASC
      OFFSET %L
      LIMIT %L
    )
    SELECT
      ls.witness, 
      ls.rank, 
      ls.url,
      ls.votes::TEXT,
      ls.votes_daily_change::TEXT,
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
      (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC,
      (CASE WHEN %L = 'desc' THEN witness_id ELSE NULL END) DESC,
      (CASE WHEN %L = 'asc' THEN witness_id ELSE NULL END) ASC

    $query$,
    "direction", "sort", "direction", "sort", "direction", "direction", _offset,"page-size",
    "direction", "sort", "direction", "sort", "direction", "direction"
  );

END
$$;

DROP FUNCTION IF EXISTS hafbe_backend.get_witness;
CREATE OR REPLACE FUNCTION hafbe_backend.get_witness(
    _witness_id INT
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
        cw.witness_id,
        (SELECT av.name FROM hive.accounts_view av WHERE av.id = _witness_id)::TEXT AS witness,
        COALESCE(cw.url, '') AS url,
        COALESCE(cw.price_feed, '0.000'::NUMERIC) AS price_feed,
        COALESCE(cw.bias, 0) AS bias,
        COALESCE(cw.feed_updated_at, '1970-01-01 00:00:00'::TIMESTAMP) AS feed_updated_at,
        COALESCE(cw.block_size, 0) AS block_size,
        COALESCE(cw.signing_key, '') AS signing_key, 
        COALESCE(cw.version, '0.0.0') AS version,
        COALESCE(cw.missed_blocks, 0) AS missed_blocks,
        COALESCE(cw.hbd_interest_rate,0) AS hbd_interest_rate,
        COALESCE(cw.last_created_block_num,0) AS last_created_block_num,
        COALESCE(cw.account_creation_fee,0) AS account_creation_fee
      FROM hafbe_app.current_witnesses cw 
      WHERE cw.witness_id = _witness_id
    )
    SELECT ROW(
      ls.witness, 
      all_votes.rank, 
      ls.url,
      COALESCE(all_votes.votes::TEXT, '0'),
      COALESCE(wvcc.votes_daily_change::TEXT, '0'),
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
