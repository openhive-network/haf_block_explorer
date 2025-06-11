SET ROLE hafbe_owner;

DROP FUNCTION IF EXISTS hafbe_backend.get_witness_voters;
CREATE OR REPLACE FUNCTION hafbe_backend.get_witness_voters(
    "witness" INT,
    "filter_account" INT,
    "page" INT,
    "page-size" INT,
    "sort" hafbe_types.order_by_votes,
    "direction" hafbe_types.sort_direction
)
RETURNS SETOF hafbe_types.witness_voter 
-- openapi-generated-code-end
LANGUAGE 'plpgsql'
STABLE
SET plan_cache_mode = force_custom_plan
AS
$$
DECLARE
  _offset INT := ((("page" - 1) * "page-size"));
BEGIN
  RETURN QUERY (
    WITH limited_set AS MATERIALIZED (
      SELECT 
        av.name,
        avs.vests, 
        avs.account_vests,
        avs.proxied_vests,
        bv.created_at
      FROM hafbe_app.current_witness_votes cwv
      JOIN hafbe_app.account_vest_stats_cache avs ON avs.account_id = cwv.voter_id
      JOIN hive.blocks_view bv ON bv.num = cwv.source_op_block
      JOIN hive.accounts_view av ON av.id = cwv.voter_id
      WHERE 
        cwv.witness_id = "witness" AND
        ("filter_account" IS NULL OR cwv.voter_id = "filter_account")
      ORDER BY
        (CASE WHEN "direction" = 'desc' AND "sort" = 'vests'          THEN avs.vests           ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'  AND "sort" = 'vests'          THEN avs.vests           ELSE NULL END) ASC,
        (CASE WHEN "direction" = 'desc' AND "sort" = 'account_vests'  THEN avs.account_vests   ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'  AND "sort" = 'account_vests'  THEN avs.account_vests   ELSE NULL END) ASC,
        (CASE WHEN "direction" = 'desc' AND "sort" = 'proxied_vests'  THEN avs.proxied_vests   ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'  AND "sort" = 'proxied_vests'  THEN avs.proxied_vests   ELSE NULL END) ASC,
        (CASE WHEN "direction" = 'desc' AND "sort" = 'voter'          THEN av.name             ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'  AND "sort" = 'voter'          THEN av.name             ELSE NULL END) ASC,
        (CASE WHEN "direction" = 'desc' AND "sort" = 'timestamp'      THEN cwv.source_op_block ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'  AND "sort" = 'timestamp'      THEN cwv.source_op_block ELSE NULL END) ASC,
        (CASE WHEN "direction" = 'desc'                               THEN cwv.voter_id        ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'                                THEN cwv.voter_id        ELSE NULL END) ASC
      OFFSET _offset  
      LIMIT "page-size"
    )
    SELECT 
      ls.name::TEXT,
      ls.vests::TEXT,
      ls.account_vests::TEXT,
      ls.proxied_vests::TEXT,
      ls.created_at
    FROM limited_set ls
  );

END
$$;

DROP FUNCTION IF EXISTS hafbe_backend.get_witness_votes_history;
CREATE OR REPLACE FUNCTION hafbe_backend.get_witness_votes_history(
    "witness" INT,
    "filter_account" INT,
    "page" INT,
    "page-size" INT,
    "direction" hafbe_types.sort_direction,
    "from-block" INT,
    "to-block" INT 
)
RETURNS SETOF hafbe_types.witness_votes_history_record 
LANGUAGE 'plpgsql'
STABLE
SET plan_cache_mode = force_custom_plan
AS
$$
DECLARE
  _offset INT := ((("page" - 1) * "page-size"));
BEGIN
  RETURN QUERY (
    WITH limited_set AS MATERIALIZED (
      SELECT 
        av.name,
        cwv.voter_id,
        cwv.approve,
        avs.vests, 
        avs.account_vests,
        avs.proxied_vests,
        cwv.source_op_block,
        bv.created_at
      FROM hafbe_app.witness_votes_history cwv
      -- this table holds vest stats for CURRENT voters (if a voter took out his vote and never voted again, his stats are not available in this table)
      LEFT JOIN hafbe_app.account_vest_stats_cache avs ON avs.account_id = cwv.voter_id
      JOIN hive.blocks_view bv ON bv.num = cwv.source_op_block
      JOIN hive.accounts_view av ON av.id = cwv.voter_id
      WHERE 
        cwv.witness_id = "witness" AND
        ("filter_account" IS NULL OR cwv.voter_id = "filter_account"    ) AND
        ("from-block" IS NULL     OR cwv.source_op_block >= "from-block") AND
        ("to-block" IS NULL       OR cwv.source_op_block <= "to-block"  )
      ORDER BY
        (CASE WHEN "direction" = 'desc' THEN cwv.source_op_block ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'  THEN cwv.source_op_block ELSE NULL END) ASC,
        (CASE WHEN "direction" = 'desc' THEN cwv.voter_id        ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'  THEN cwv.voter_id        ELSE NULL END) ASC
      OFFSET _offset  
      LIMIT "page-size"
    ),
    empty_results AS (
      SELECT 
        ls.name,
        ls.voter_id,
        ls.approve,
        evs.vests,
        evs.account_vests,
        evs.proxied_vests,
        ls.source_op_block,
        ls.created_at
      FROM limited_set ls
      JOIN hafbe_backend.expired_voter_stats_view evs ON evs.account_id = ls.voter_id
      WHERE ls.vests IS NULL
    ),
    not_empty_results AS (
      SELECT 
        ls.name,
        ls.voter_id,
        ls.approve,
        ls.vests,
        ls.account_vests,
        ls.proxied_vests,
        ls.source_op_block,
        ls.created_at 
      FROM limited_set ls
      WHERE ls.vests IS NOT NULL
    ),
    union_results AS (
      SELECT * FROM empty_results
      UNION ALL
      SELECT * FROM not_empty_results
    )
    SELECT 
      ur.name::TEXT,
      ur.approve,
      ur.vests::TEXT,
      ur.account_vests::TEXT,
      ur.proxied_vests::TEXT,
      ur.created_at
    FROM union_results ur
    ORDER BY
      (CASE WHEN "direction" = 'desc' THEN ur.source_op_block ELSE NULL END) DESC,
      (CASE WHEN "direction" = 'asc'  THEN ur.source_op_block ELSE NULL END) ASC,
      (CASE WHEN "direction" = 'desc' THEN ur.voter_id        ELSE NULL END) DESC,
      (CASE WHEN "direction" = 'asc'  THEN ur.voter_id        ELSE NULL END) ASC
  );
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
SET plan_cache_mode = force_custom_plan
AS
$$
DECLARE
  _offset INT := ((("page" - 1) * "page-size"));
BEGIN
  RETURN QUERY (
    WITH limited_set AS 
    (
      SELECT
        cw.witness_id, 
        av.name,
		    a.rank,
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
      JOIN hive.accounts_view av                       ON av.id = cw.witness_id
	    JOIN hafbe_app.witness_rank_cache a              ON a.witness_id = cw.witness_id
      LEFT JOIN hafbe_app.witness_votes_cache b        ON b.witness_id = cw.witness_id
      LEFT JOIN hafbe_app.witness_votes_change_cache c ON c.witness_id = cw.witness_id
      ORDER BY
        (CASE WHEN "direction" = 'desc' AND "sort" = 'witness'                 THEN av.name                                                        ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'  AND "sort" = 'witness'                 THEN av.name                                                        ELSE NULL END) ASC,
        (CASE WHEN "direction" = 'desc' AND "sort" = 'rank'                    THEN a.rank                                                         ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'  AND "sort" = 'rank'                    THEN a.rank                                                         ELSE NULL END) ASC,
        (CASE WHEN "direction" = 'desc' AND "sort" = 'url'                     THEN COALESCE(cw.url, '')                                           ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'  AND "sort" = 'url'                     THEN COALESCE(cw.url, '')                                           ELSE NULL END) ASC,
        (CASE WHEN "direction" = 'desc' AND "sort" = 'votes'                   THEN a.rank                                                         ELSE NULL END) ASC,
        (CASE WHEN "direction" = 'asc'  AND "sort" = 'votes'                   THEN a.rank                                                         ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'desc' AND "sort" = 'votes_daily_change'      THEN COALESCE(c.votes_daily_change, 0)                              ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'  AND "sort" = 'votes_daily_change'      THEN COALESCE(c.votes_daily_change, 0)                              ELSE NULL END) ASC,
        (CASE WHEN "direction" = 'desc' AND "sort" = 'voters_num'              THEN COALESCE(b.voters_num,0)                                       ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'  AND "sort" = 'voters_num'              THEN COALESCE(b.voters_num,0)                                       ELSE NULL END) ASC,
        (CASE WHEN "direction" = 'desc' AND "sort" = 'voters_num_daily_change' THEN COALESCE(c.voters_num_daily_change,0)                          ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'  AND "sort" = 'voters_num_daily_change' THEN COALESCE(c.voters_num_daily_change,0)                          ELSE NULL END) ASC,
        (CASE WHEN "direction" = 'desc' AND "sort" = 'price_feed'              THEN COALESCE(cw.price_feed, '0.000'::NUMERIC)                      ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'  AND "sort" = 'price_feed'              THEN COALESCE(cw.price_feed, '0.000'::NUMERIC)                      ELSE NULL END) ASC,
        (CASE WHEN "direction" = 'desc' AND "sort" = 'bias'                    THEN COALESCE(cw.bias, 0)                                           ELSE NULL END) ASC,
        (CASE WHEN "direction" = 'asc'  AND "sort" = 'bias'                    THEN COALESCE(cw.bias, 0)                                           ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'desc' AND "sort" = 'block_size'              THEN COALESCE(cw.block_size, 0)                                     ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'  AND "sort" = 'block_size'              THEN COALESCE(cw.block_size, 0)                                     ELSE NULL END) ASC,
        (CASE WHEN "direction" = 'desc' AND "sort" = 'signing_key'             THEN COALESCE(cw.signing_key, '')                                   ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'  AND "sort" = 'signing_key'             THEN COALESCE(cw.signing_key, '')                                   ELSE NULL END) ASC,
        (CASE WHEN "direction" = 'desc' AND "sort" = 'version'                 THEN COALESCE(cw.version, '0.0.0')                                  ELSE NULL END) ASC,
        (CASE WHEN "direction" = 'asc'  AND "sort" = 'version'                 THEN COALESCE(cw.version, '0.0.0')                                  ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'desc' AND "sort" = 'feed_updated_at'         THEN COALESCE(cw.feed_updated_at, '1970-01-01 00:00:00'::TIMESTAMP) ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'  AND "sort" = 'feed_updated_at'         THEN COALESCE(cw.feed_updated_at, '1970-01-01 00:00:00'::TIMESTAMP) ELSE NULL END) ASC,
        (CASE WHEN "direction" = 'desc'                                        THEN cw.witness_id                                                  ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'                                         THEN cw.witness_id                                                  ELSE NULL END) ASC
      OFFSET _offset  
      LIMIT "page-size"
    )
    SELECT
      ls.name::TEXT, 
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
    FROM limited_set ls
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
