-- =============================================================================
-- Witness Helper Functions
-- =============================================================================
-- Functions for retrieving witness information including voters, vote history,
-- witness lists, and statistics. Supports flexible sorting and pagination.
-- =============================================================================

SET ROLE hafbe_owner;

-- =============================================================================
-- SECTION 1: Witness Voter Functions
-- =============================================================================

/*
 * get_witness_voters: Gets paginated list of accounts voting for a witness.
 *
 * Returns voter information including their vesting power breakdown
 * (account vests vs proxied vests).
 *
 * PARAMETERS:
 *   witness        - Witness account ID to get voters for
 *   filter_account - Optional: filter to specific voter (for search)
 *   page           - Page number (1-based)
 *   page-size      - Number of voters per page
 *   sort           - Sort field: 'vests', 'account_vests', 'proxied_vests', 'voter', 'timestamp'
 *   direction      - Sort direction: 'asc' or 'desc'
 *
 * RETURNS: Set of witness_voter records with voter details
 *
 * NOTE: Uses force_custom_plan due to dynamic parameter values that would
 * cause suboptimal generic plans.
 */
DROP FUNCTION IF EXISTS hafbe_backend.get_witness_voters;
CREATE OR REPLACE FUNCTION hafbe_backend.get_witness_voters(
    "witness"        INT,
    "filter_account" INT,
    "page"           INT,
    "page-size"      INT,
    "sort"           hafbe_backend.order_by_votes,
    "direction"      hafbe_backend.sort_direction
)
RETURNS SETOF hafbe_backend.witness_voter
LANGUAGE plpgsql STABLE
SET plan_cache_mode = force_custom_plan
AS
$$
DECLARE
  __offset INT := ((("page" - 1) * "page-size"));
BEGIN
  RETURN QUERY (
    /*
     * =========================================================================
     * CTE: limited_set
     * =========================================================================
     * WHY MATERIALIZED: Pagination must happen before the per-row lookups.
     *
     * PURPOSE: Fetch voters with their vesting stats, sorted and paginated.
     *
     * JOINS:
     *   - current_witness_votes_view: Active votes for the witness
     *   - account_vest_stats_cache: Pre-calculated vest breakdowns
     *   - accounts_view: Voter name, probed per voter only when sorting by it
     *
     * WHY LATERAL LOOKUPS: Joining the HAF context views (accounts_view,
     * blocks_view) on a key inflates their row estimates, and the planner
     * then scans all accounts or all blocks. A LIMIT 1 probe per row is
     * always an index lookup.
     *
     * DYNAMIC SORT:
     *   Uses CASE expressions to enable sorting by different columns.
     *   Each sort field has ASC and DESC variants. Only one CASE matches
     *   per row; others return NULL and are ignored.
     */
    WITH limited_set AS MATERIALIZED (
      SELECT
        cwv.voter_id,
        cwv.source_op_block,
        avs.vests,
        avs.account_vests,
        avs.proxied_vests
      FROM hafbe_backend.current_witness_votes_view cwv
      JOIN hafbe_app.account_vest_stats_cache avs ON avs.account_id = cwv.voter_id
      LEFT JOIN LATERAL (
        SELECT av.name
        FROM hive.accounts_view av
        WHERE av.id = cwv.voter_id AND "sort" = 'voter'
        LIMIT 1
      ) vn ON TRUE
      WHERE
        cwv.witness_id = "witness" AND
        ("filter_account" IS NULL OR cwv.voter_id = "filter_account")
      ORDER BY
        -- Sort by total vests (account + proxied)
        (CASE WHEN "direction" = 'desc' AND "sort" = 'vests'          THEN avs.vests           ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'  AND "sort" = 'vests'          THEN avs.vests           ELSE NULL END) ASC,
        -- Sort by account's own vests only
        (CASE WHEN "direction" = 'desc' AND "sort" = 'account_vests'  THEN avs.account_vests   ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'  AND "sort" = 'account_vests'  THEN avs.account_vests   ELSE NULL END) ASC,
        -- Sort by vests received via proxy
        (CASE WHEN "direction" = 'desc' AND "sort" = 'proxied_vests'  THEN avs.proxied_vests   ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'  AND "sort" = 'proxied_vests'  THEN avs.proxied_vests   ELSE NULL END) ASC,
        -- Sort by voter name alphabetically
        (CASE WHEN "direction" = 'desc' AND "sort" = 'voter'          THEN vn.name             ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'  AND "sort" = 'voter'          THEN vn.name             ELSE NULL END) ASC,
        -- Sort by vote timestamp (using block number as proxy)
        (CASE WHEN "direction" = 'desc' AND "sort" = 'timestamp'      THEN cwv.source_op_block ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'  AND "sort" = 'timestamp'      THEN cwv.source_op_block ELSE NULL END) ASC,
        -- Tiebreaker: voter_id for stable ordering
        (CASE WHEN "direction" = 'desc'                               THEN cwv.voter_id        ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'                                THEN cwv.voter_id        ELSE NULL END) ASC
      OFFSET __offset
      LIMIT "page-size"
    )
    -- Cast numeric values to TEXT to avoid JSON compression issues with large numbers
    SELECT
      av.name::TEXT,
      ls.vests::TEXT,
      ls.account_vests::TEXT,
      ls.proxied_vests::TEXT,
      bv.created_at
    FROM limited_set ls
    CROSS JOIN LATERAL (
      SELECT a.name
      FROM hive.accounts_view a
      WHERE a.id = ls.voter_id
      LIMIT 1
    ) av
    CROSS JOIN LATERAL (
      SELECT b.created_at
      FROM hive.blocks_view b
      WHERE b.num = ls.source_op_block
      LIMIT 1
    ) bv
  );
END
$$;

/*
 * get_witness_votes_history: Gets historical voting records for a witness.
 *
 * Returns vote history including both approve and unapprove actions.
 * Handles cases where voters no longer have current stats by falling
 * back to expired voter stats.
 *
 * Each row carries its cause, from the operation behind it (source_op), with the
 * names of the witness vote change breakdown (#214): votes_cast for an approval
 * (always account_witness_vote); for a removal votes_removed (account_witness_vote),
 * proxy (account_witness_proxy: setting a proxy removes all the voter's witness
 * votes), expired (expired_account_notification) or declined
 * (declined_voting_rights); NULL if the operation is not found (the breakdown counts
 * such a removal as votes_removed instead). A proxy removal
 * also carries proxy_name, the proxy that operation set (account_proxies_history at
 * the same account and source_op). The operation is read through
 * hafbe_app.operations_view, which covers reversible blocks too (not
 * witness_votes_history_view.op_type_id, which reads hafd.operations only).
 *
 * PARAMETERS:
 *   witness        - Witness account ID
 *   filter_account - Optional: filter to specific voter
 *   page           - Page number (1-based)
 *   page-size      - Number of records per page
 *   direction      - Sort direction: 'asc' or 'desc'
 *   from-block     - Optional: starting block filter
 *   to-block       - Optional: ending block filter
 *
 * RETURNS: Set of witness_votes_history_record with vote details
 */
DROP FUNCTION IF EXISTS hafbe_backend.get_witness_votes_history;
CREATE OR REPLACE FUNCTION hafbe_backend.get_witness_votes_history(
    "witness"        INT,
    "filter_account" INT,
    "page"           INT,
    "page-size"      INT,
    "direction"      hafbe_backend.sort_direction,
    "from-block"     INT,
    "to-block"       INT
)
RETURNS SETOF hafbe_backend.witness_votes_history_record
LANGUAGE plpgsql STABLE
SET plan_cache_mode = force_custom_plan
AS
$$
DECLARE
  __offset      INT := ((("page" - 1) * "page-size"));
  __op_vote     INT := hafbe_backend.op_account_witness_vote();
  __op_proxy    INT := hafbe_backend.op_account_witness_proxy();
  __op_expired  INT := hafbe_backend.op_expired_account_notification();
  __op_declined INT := hafbe_backend.op_declined_voting_rights();
BEGIN
  RETURN QUERY (
    /*
     * =========================================================================
     * CTE: limited_set
     * =========================================================================
     * WHY MATERIALIZED: Pagination must happen before the per-row lookups.
     *
     * PURPOSE: Select the page from the vote rows alone, then fetch each page
     * row's stats, voter name, block timestamp, cause and proxy. Every vote has a
     * voter account and a block, so enriching after OFFSET picks the same rows;
     * enriching first joined them for every vote the OFFSET skipped.
     *
     * NOTE: Uses LEFT JOIN to account_vest_stats_cache because voters who
     * removed their vote won't have current stats. These will be filled
     * from expired_voter_stats_view in later CTEs.
     */
    WITH paged_votes AS MATERIALIZED (
      SELECT
        cwv.voter_id,
        cwv.approve,
        cwv.source_op,
        cwv.source_op_block
      FROM hafbe_backend.witness_votes_history_view cwv
      WHERE
        cwv.witness_id = "witness" AND
        ("filter_account" IS NULL OR cwv.voter_id = "filter_account") AND
        ("from-block" IS NULL     OR cwv.source_op_block >= "from-block") AND
        ("to-block" IS NULL       OR cwv.source_op_block <= "to-block")
      -- source_op is the final tie-break and is NOT optional. A Hive block is 3
      -- seconds and nothing stops an account from voting and un-voting the same
      -- witness inside one block, which yields two rows identical on BOTH
      -- (source_op_block, voter_id) -- e.g. cmtzco/arhag in block 3067986. Tied rows
      -- have no defined order, so the un-vote could be returned before the vote it
      -- undid. source_op (the operation id) is monotonic within a block and unique,
      -- which makes the sort total. It must also match the post-UNION sort below,
      -- otherwise the two sorts can break the same tie in opposite directions and a
      -- page is displayed in an order the pagination did not choose.
      ORDER BY
        (CASE WHEN "direction" = 'desc' THEN cwv.source_op_block ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'  THEN cwv.source_op_block ELSE NULL END) ASC,
        (CASE WHEN "direction" = 'desc' THEN cwv.voter_id        ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'  THEN cwv.voter_id        ELSE NULL END) ASC,
        (CASE WHEN "direction" = 'desc' THEN cwv.source_op       ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'  THEN cwv.source_op       ELSE NULL END) ASC
      OFFSET __offset
      LIMIT "page-size"
    ),

    limited_set AS MATERIALIZED (
      SELECT
        av.name,
        pv.voter_id,
        pv.approve,
        c.cause,
        px.proxy_name,
        avs.vests,
        avs.account_vests,
        avs.proxied_vests,
        pv.source_op,
        pv.source_op_block,
        bv.created_at
      FROM paged_votes pv
      -- LEFT JOIN: voter may no longer be active, stats may be NULL
      LEFT JOIN hafbe_app.account_vest_stats_cache avs ON avs.account_id = pv.voter_id
      CROSS JOIN LATERAL (
        SELECT b.created_at
        FROM hive.blocks_view b
        WHERE b.num = pv.source_op_block
        LIMIT 1
      ) bv
      CROSS JOIN LATERAL (
        SELECT a.name
        FROM hive.accounts_view a
        WHERE a.id = pv.voter_id
        LIMIT 1
      ) av
      -- A removal's operation, read once: an approval is always a vote. LIMIT 1 is
      -- required: without it the planner pulls the subquery up into a hash join over
      -- the whole operations_view (a scan of every operation), instead of one
      -- primary-key lookup per page row.
      LEFT JOIN LATERAL (
        SELECT o.op_type_id
        FROM hafbe_app.operations_view o
        WHERE NOT pv.approve
          AND o.id = pv.source_op
        LIMIT 1
      ) op ON TRUE
      CROSS JOIN LATERAL (
        SELECT CASE
          WHEN pv.approve                   THEN 'votes_cast'
          WHEN op.op_type_id = __op_vote     THEN 'votes_removed'
          WHEN op.op_type_id = __op_proxy    THEN 'proxy'
          WHEN op.op_type_id = __op_expired  THEN 'expired'
          WHEN op.op_type_id = __op_declined THEN 'declined'
        END AS cause
      ) c
      LEFT JOIN LATERAL (
        SELECT pa.name AS proxy_name
        FROM hafbe_app.account_proxies_history ph
        JOIN hive.accounts_view pa ON pa.id = ph.proxy_id
        WHERE op.op_type_id = __op_proxy
          AND ph.account_id = pv.voter_id
          AND ph.source_op = pv.source_op
          AND ph.proxy
        LIMIT 1
      ) px ON TRUE
    ),

    /*
     * =========================================================================
     * CTE: empty_results
     * =========================================================================
     * PURPOSE: For voters without current stats, fetch from expired stats.
     *
     * Expired voter stats are preserved for historical accuracy even after
     * a voter removes their vote.
     */
    empty_results AS (
      SELECT
        ls.name,
        ls.voter_id,
        ls.approve,
        ls.cause,
        ls.proxy_name,
        evs.vests,
        evs.account_vests,
        evs.proxied_vests,
        ls.source_op,
        ls.source_op_block,
        ls.created_at
      FROM limited_set ls
      JOIN hafbe_backend.expired_voter_stats_view evs ON evs.account_id = ls.voter_id
      WHERE ls.vests IS NULL
    ),

    /*
     * =========================================================================
     * CTE: not_empty_results
     * =========================================================================
     * PURPOSE: Pass through records that already have stats.
     */
    not_empty_results AS (
      SELECT
        ls.name,
        ls.voter_id,
        ls.approve,
        ls.cause,
        ls.proxy_name,
        ls.vests,
        ls.account_vests,
        ls.proxied_vests,
        ls.source_op,
        ls.source_op_block,
        ls.created_at
      FROM limited_set ls
      WHERE ls.vests IS NOT NULL
    ),

    /*
     * =========================================================================
     * CTE: union_results
     * =========================================================================
     * PURPOSE: Combine records with and without current stats.
     */
    union_results AS (
      SELECT * FROM empty_results
      UNION ALL
      SELECT * FROM not_empty_results
    )

    SELECT
      ur.name::TEXT,
      ur.approve,
      ur.cause,
      ur.proxy_name::TEXT,
      ur.vests::TEXT,
      ur.account_vests::TEXT,
      ur.proxied_vests::TEXT,
      ur.created_at
    FROM union_results ur
    -- Re-apply sort after UNION (UNION ALL destroys limited_set's ordering).
    -- Keys MUST match limited_set's exactly, source_op included -- see the note there.
    ORDER BY
      (CASE WHEN "direction" = 'desc' THEN ur.source_op_block ELSE NULL END) DESC,
      (CASE WHEN "direction" = 'asc'  THEN ur.source_op_block ELSE NULL END) ASC,
      (CASE WHEN "direction" = 'desc' THEN ur.voter_id        ELSE NULL END) DESC,
      (CASE WHEN "direction" = 'asc'  THEN ur.voter_id        ELSE NULL END) ASC,
      (CASE WHEN "direction" = 'desc' THEN ur.source_op       ELSE NULL END) DESC,
      (CASE WHEN "direction" = 'asc'  THEN ur.source_op       ELSE NULL END) ASC
  );
END
$$;

-- =============================================================================
-- SECTION 2: Witness List Functions
-- =============================================================================

/*
 * witness_votes_change_breakdown: votes_change_breakdown of the given witnesses.
 *
 * One row per distinct witness in _witness_ids, none before the first refresh of
 * hafbe_app.witness_votes_change_by_cause. Per window ('today', '7d'): total and
 * voters from the 'total' row, a VESTS string per cause (0 for a cause without a
 * row), and rank_start.
 *
 * rank_start is the witness's rank at the window's start, as the refresh stored it
 * for as_of_block (hafbe_app.witness_votes_change_by_cause_start), ranked like rank.
 * A witness without a row there (registered after as_of_block) gets its rank.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.witness_votes_change_breakdown(_witness_ids INT[])
RETURNS TABLE (
    witness_id             INT,
    votes_change_breakdown JSON
)
LANGUAGE sql STABLE
AS
$$
  WITH windows AS (
    SELECT w.time_window FROM (VALUES ('today'), ('7d')) AS w (time_window)
  ),
  -- One row per witness: joined on the witness alone, so the join key is selective.
  ranks AS (
    SELECT
      s.witness_id,
      MAX(s.rank_start) FILTER (WHERE s.time_window = 'today') AS today,
      MAX(s.rank_start) FILTER (WHERE s.time_window = '7d')    AS week
    FROM hafbe_app.witness_votes_change_by_cause_start s
    WHERE s.witness_id = ANY(_witness_ids)
    GROUP BY s.witness_id
  ),
  ids AS (
    SELECT DISTINCT u.witness_id FROM unnest(_witness_ids) AS u (witness_id)
  ),
  objects AS (
    SELECT
      i.witness_id,
      w.time_window,
      json_build_object(
        'total',           COALESCE(SUM(c.vests) FILTER (WHERE c.cause = 'total'), 0)::TEXT,
        'voters',          COALESCE(SUM(c.voters) FILTER (WHERE c.cause = 'total'), 0)::INT,
        'rank_start',      MAX(CASE w.time_window
                             WHEN 'today' THEN COALESCE(r.today, rc.rank)
                             ELSE COALESCE(r.week, rc.rank)
                           END),
        'votes_cast',      COALESCE(SUM(c.vests) FILTER (WHERE c.cause = 'votes_cast'), 0)::TEXT,
        'votes_removed',   COALESCE(SUM(c.vests) FILTER (WHERE c.cause = 'votes_removed'), 0)::TEXT,
        'power_down',      COALESCE(SUM(c.vests) FILTER (WHERE c.cause = 'power_down'), 0)::TEXT,
        'power_up',        COALESCE(SUM(c.vests) FILTER (WHERE c.cause = 'power_up'), 0)::TEXT,
        'producer_reward', COALESCE(SUM(c.vests) FILTER (WHERE c.cause = 'producer_reward'), 0)::TEXT,
        'claimed_reward',  COALESCE(SUM(c.vests) FILTER (WHERE c.cause = 'claimed_reward'), 0)::TEXT,
        'proxy',           COALESCE(SUM(c.vests) FILTER (WHERE c.cause = 'proxy'), 0)::TEXT,
        'expired',         COALESCE(SUM(c.vests) FILTER (WHERE c.cause = 'expired'), 0)::TEXT,
        'declined',        COALESCE(SUM(c.vests) FILTER (WHERE c.cause = 'declined'), 0)::TEXT
      ) AS window_object
    FROM ids i
    CROSS JOIN windows w
    LEFT JOIN ranks r ON r.witness_id = i.witness_id
    LEFT JOIN hafbe_app.witness_rank_cache rc ON rc.witness_id = i.witness_id
    LEFT JOIN hafbe_app.witness_votes_change_by_cause c
      ON c.witness_id = i.witness_id
      AND c.time_window = w.time_window
    GROUP BY i.witness_id, w.time_window
  )
  SELECT
    o.witness_id,
    json_build_object(
      'as_of_block', st.as_of_block,
      'today', (array_agg(o.window_object) FILTER (WHERE o.time_window = 'today'))[1],
      '7d',    (array_agg(o.window_object) FILTER (WHERE o.time_window = '7d'))[1]
    )
  FROM objects o
  CROSS JOIN hafbe_app.witness_votes_change_by_cause_state st
  GROUP BY o.witness_id, st.as_of_block
$$;

/*
 * get_witnesses: Gets paginated list of all witnesses with statistics.
 *
 * Returns comprehensive witness data including votes, daily changes,
 * price feed, and configuration parameters.
 *
 * PARAMETERS:
 *   page      - Page number (1-based)
 *   page-size - Number of witnesses per page
 *   sort      - Sort field (see order_by_witness enum for options)
 *   direction - Sort direction: 'asc' or 'desc'
 *
 * RETURNS: Set of witness records with all statistics
 *
 * DATA SOURCES:
 *   - current_witnesses: Core witness configuration
 *   - witness_rank_cache: Pre-calculated rank
 *   - witness_votes_cache: Total votes and voter count
 *   - witness_votes_change_cache: Daily vote changes
 *   - witness_votes_change_by_cause: Vote change by cause (witness_votes_change_breakdown)
 */
DROP FUNCTION IF EXISTS hafbe_backend.get_witnesses;
CREATE OR REPLACE FUNCTION hafbe_backend.get_witnesses(
    "page"      INT,
    "page-size" INT,
    "sort"      hafbe_backend.order_by_witness,
    "direction" hafbe_backend.sort_direction
)
RETURNS SETOF hafbe_backend.witness
LANGUAGE plpgsql STABLE
SET plan_cache_mode = force_custom_plan
AS
$$
DECLARE
  __offset INT := ((("page" - 1) * "page-size"));
BEGIN
  RETURN QUERY (
    -- Paginate before resolving names: joining hive.accounts_view inflates its
    -- estimate and the planner scans every account. When the name is the sort
    -- key, witness_page resolves all names in one id = ANY(array) lookup and
    -- pages them on (id, name) alone, and limited_set only enriches that page.
    -- For every other sort witness_page folds to an empty result in the custom
    -- plan, and names are probed once per page row below.
    WITH witness_page AS MATERIALIZED (
      SELECT av.id, av.name
      FROM hive.accounts_view av
      WHERE
        "sort" = 'witness' AND
        av.id = ANY(ARRAY(
          SELECT cw.witness_id
          FROM hafbe_app.current_witnesses cw
          JOIN hafbe_app.witness_rank_cache a ON a.witness_id = cw.witness_id
        ))
      ORDER BY
        (CASE WHEN "direction" = 'desc' THEN av.name ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'  THEN av.name ELSE NULL END) ASC,
        (CASE WHEN "direction" = 'desc' THEN av.id   ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'  THEN av.id   ELSE NULL END) ASC
      OFFSET __offset
      LIMIT "page-size"
    ),
    limited_set AS MATERIALIZED (
      SELECT
        cw.witness_id,
        a.rank,
        -- COALESCE provides defaults for witnesses without data
        COALESCE(cw.url, '')                                AS url,
        COALESCE(cw.price_feed, '0.000'::NUMERIC)           AS price_feed,
        COALESCE(cw.bias, 0)                                AS bias,
        COALESCE(cw.feed_updated_at, '1970-01-01 00:00:00'::TIMESTAMP) AS feed_updated_at,
        COALESCE(cw.block_size, 0)                          AS block_size,
        COALESCE(cw.signing_key, '')                        AS signing_key,
        COALESCE(cw.version, '0.0.0')                       AS version,
        COALESCE(cw.missed_blocks, 0)                       AS missed_blocks,
        COALESCE(b.votes, 0)                                AS votes,
        COALESCE(b.voters_num, 0)                           AS voters_num,
        COALESCE(c.votes_daily_change, 0)                   AS votes_daily_change,
        COALESCE(c.voters_num_daily_change, 0)              AS voters_num_daily_change,
        COALESCE(cw.hbd_interest_rate, 0)                   AS hbd_interest_rate,
        COALESCE(cw.last_created_block_num, 0)              AS last_created_block_num,
        COALESCE(cw.account_creation_fee, 0)                AS account_creation_fee
      FROM hafbe_app.current_witnesses cw
      JOIN hafbe_app.witness_rank_cache a              ON a.witness_id = cw.witness_id
      LEFT JOIN hafbe_app.witness_votes_cache b        ON b.witness_id = cw.witness_id
      LEFT JOIN hafbe_app.witness_votes_change_cache c ON c.witness_id = cw.witness_id
      LEFT JOIN witness_page wn ON wn.id = cw.witness_id
      WHERE "sort" <> 'witness' OR wn.id IS NOT NULL
      ORDER BY
        -- Sort by witness name
        (CASE WHEN "direction" = 'desc' AND "sort" = 'witness'                 THEN wn.name                                                        ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'  AND "sort" = 'witness'                 THEN wn.name                                                        ELSE NULL END) ASC,
        -- Sort by rank
        (CASE WHEN "direction" = 'desc' AND "sort" = 'rank'                    THEN a.rank                                                         ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'  AND "sort" = 'rank'                    THEN a.rank                                                         ELSE NULL END) ASC,
        -- Sort by URL
        (CASE WHEN "direction" = 'desc' AND "sort" = 'url'                     THEN COALESCE(cw.url, '')                                           ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'  AND "sort" = 'url'                     THEN COALESCE(cw.url, '')                                           ELSE NULL END) ASC,
        -- Sort by votes (uses rank for efficiency - rank is derived from votes)
        (CASE WHEN "direction" = 'asc'  AND "sort" = 'votes'                   THEN a.rank                                                         ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'desc' AND "sort" = 'votes'                   THEN a.rank                                                         ELSE NULL END) ASC,
        -- Sort by daily vote change
        (CASE WHEN "direction" = 'desc' AND "sort" = 'votes_daily_change'      THEN COALESCE(c.votes_daily_change, 0)                              ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'  AND "sort" = 'votes_daily_change'      THEN COALESCE(c.votes_daily_change, 0)                              ELSE NULL END) ASC,
        -- Sort by number of voters
        (CASE WHEN "direction" = 'desc' AND "sort" = 'voters_num'              THEN COALESCE(b.voters_num, 0)                                      ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'  AND "sort" = 'voters_num'              THEN COALESCE(b.voters_num, 0)                                      ELSE NULL END) ASC,
        -- Sort by daily voter count change
        (CASE WHEN "direction" = 'desc' AND "sort" = 'voters_num_daily_change' THEN COALESCE(c.voters_num_daily_change, 0)                         ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'  AND "sort" = 'voters_num_daily_change' THEN COALESCE(c.voters_num_daily_change, 0)                         ELSE NULL END) ASC,
        -- Sort by price feed
        (CASE WHEN "direction" = 'desc' AND "sort" = 'price_feed'              THEN COALESCE(cw.price_feed, '0.000'::NUMERIC)                      ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'  AND "sort" = 'price_feed'              THEN COALESCE(cw.price_feed, '0.000'::NUMERIC)                      ELSE NULL END) ASC,
        -- Sort by feed bias
        (CASE WHEN "direction" = 'desc' AND "sort" = 'bias'                    THEN COALESCE(cw.bias, 0)                                           ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'  AND "sort" = 'bias'                    THEN COALESCE(cw.bias, 0)                                           ELSE NULL END) ASC,
        -- Sort by preferred block size
        (CASE WHEN "direction" = 'desc' AND "sort" = 'block_size'              THEN COALESCE(cw.block_size, 0)                                     ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'  AND "sort" = 'block_size'              THEN COALESCE(cw.block_size, 0)                                     ELSE NULL END) ASC,
        -- Sort by signing key
        (CASE WHEN "direction" = 'desc' AND "sort" = 'signing_key'             THEN COALESCE(cw.signing_key, '')                                   ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'  AND "sort" = 'signing_key'             THEN COALESCE(cw.signing_key, '')                                   ELSE NULL END) ASC,
        -- Sort by node version
        (CASE WHEN "direction" = 'desc' AND "sort" = 'version'                 THEN COALESCE(cw.version, '0.0.0')                                  ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'  AND "sort" = 'version'                 THEN COALESCE(cw.version, '0.0.0')                                  ELSE NULL END) ASC,
        -- Sort by feed update time
        (CASE WHEN "direction" = 'desc' AND "sort" = 'feed_updated_at'         THEN COALESCE(cw.feed_updated_at, '1970-01-01 00:00:00'::TIMESTAMP) ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'  AND "sort" = 'feed_updated_at'         THEN COALESCE(cw.feed_updated_at, '1970-01-01 00:00:00'::TIMESTAMP) ELSE NULL END) ASC,
        -- Tiebreaker: witness_id for stable ordering
        (CASE WHEN "direction" = 'desc'                                        THEN cw.witness_id                                                  ELSE NULL END) DESC,
        (CASE WHEN "direction" = 'asc'                                         THEN cw.witness_id                                                  ELSE NULL END) ASC
      OFFSET (CASE WHEN "sort" = 'witness' THEN 0 ELSE __offset END)
      LIMIT "page-size"
    )
    SELECT
      wav.name::TEXT,
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
      ls.account_creation_fee,
      vcb.votes_change_breakdown
    FROM limited_set ls
    CROSS JOIN LATERAL (
      SELECT av.name
      FROM hive.accounts_view av
      WHERE av.id = ls.witness_id
      LIMIT 1
    ) wav
    LEFT JOIN hafbe_backend.witness_votes_change_breakdown(ARRAY(SELECT l.witness_id FROM limited_set l)) vcb
      ON vcb.witness_id = ls.witness_id
    -- Re-apply limited_set's sort: the joins above need not keep it.
    -- Keys MUST match limited_set's exactly; wav.name is wn.name (the same account).
    ORDER BY
      (CASE WHEN "direction" = 'desc' AND "sort" = 'witness'                 THEN wav.name                   ELSE NULL END) DESC,
      (CASE WHEN "direction" = 'asc'  AND "sort" = 'witness'                 THEN wav.name                   ELSE NULL END) ASC,
      (CASE WHEN "direction" = 'desc' AND "sort" = 'rank'                    THEN ls.rank                    ELSE NULL END) DESC,
      (CASE WHEN "direction" = 'asc'  AND "sort" = 'rank'                    THEN ls.rank                    ELSE NULL END) ASC,
      (CASE WHEN "direction" = 'desc' AND "sort" = 'url'                     THEN ls.url                     ELSE NULL END) DESC,
      (CASE WHEN "direction" = 'asc'  AND "sort" = 'url'                     THEN ls.url                     ELSE NULL END) ASC,
      (CASE WHEN "direction" = 'asc'  AND "sort" = 'votes'                   THEN ls.rank                    ELSE NULL END) DESC,
      (CASE WHEN "direction" = 'desc' AND "sort" = 'votes'                   THEN ls.rank                    ELSE NULL END) ASC,
      (CASE WHEN "direction" = 'desc' AND "sort" = 'votes_daily_change'      THEN ls.votes_daily_change      ELSE NULL END) DESC,
      (CASE WHEN "direction" = 'asc'  AND "sort" = 'votes_daily_change'      THEN ls.votes_daily_change      ELSE NULL END) ASC,
      (CASE WHEN "direction" = 'desc' AND "sort" = 'voters_num'              THEN ls.voters_num              ELSE NULL END) DESC,
      (CASE WHEN "direction" = 'asc'  AND "sort" = 'voters_num'              THEN ls.voters_num              ELSE NULL END) ASC,
      (CASE WHEN "direction" = 'desc' AND "sort" = 'voters_num_daily_change' THEN ls.voters_num_daily_change ELSE NULL END) DESC,
      (CASE WHEN "direction" = 'asc'  AND "sort" = 'voters_num_daily_change' THEN ls.voters_num_daily_change ELSE NULL END) ASC,
      (CASE WHEN "direction" = 'desc' AND "sort" = 'price_feed'              THEN ls.price_feed              ELSE NULL END) DESC,
      (CASE WHEN "direction" = 'asc'  AND "sort" = 'price_feed'              THEN ls.price_feed              ELSE NULL END) ASC,
      (CASE WHEN "direction" = 'desc' AND "sort" = 'bias'                    THEN ls.bias                    ELSE NULL END) DESC,
      (CASE WHEN "direction" = 'asc'  AND "sort" = 'bias'                    THEN ls.bias                    ELSE NULL END) ASC,
      (CASE WHEN "direction" = 'desc' AND "sort" = 'block_size'              THEN ls.block_size              ELSE NULL END) DESC,
      (CASE WHEN "direction" = 'asc'  AND "sort" = 'block_size'              THEN ls.block_size              ELSE NULL END) ASC,
      (CASE WHEN "direction" = 'desc' AND "sort" = 'signing_key'             THEN ls.signing_key             ELSE NULL END) DESC,
      (CASE WHEN "direction" = 'asc'  AND "sort" = 'signing_key'             THEN ls.signing_key             ELSE NULL END) ASC,
      (CASE WHEN "direction" = 'desc' AND "sort" = 'version'                 THEN ls.version                 ELSE NULL END) DESC,
      (CASE WHEN "direction" = 'asc'  AND "sort" = 'version'                 THEN ls.version                 ELSE NULL END) ASC,
      (CASE WHEN "direction" = 'desc' AND "sort" = 'feed_updated_at'         THEN ls.feed_updated_at         ELSE NULL END) DESC,
      (CASE WHEN "direction" = 'asc'  AND "sort" = 'feed_updated_at'         THEN ls.feed_updated_at         ELSE NULL END) ASC,
      (CASE WHEN "direction" = 'desc'                                        THEN ls.witness_id              ELSE NULL END) DESC,
      (CASE WHEN "direction" = 'asc'                                         THEN ls.witness_id              ELSE NULL END) ASC
  );
END
$$;

/*
 * get_witness: Gets detailed information for a single witness.
 *
 * PARAMETERS:
 *   _witness_id - Witness account ID
 *
 * RETURNS: Single witness record with all statistics
 */
DROP FUNCTION IF EXISTS hafbe_backend.get_witness;
CREATE OR REPLACE FUNCTION hafbe_backend.get_witness(
    _witness_id INT
)
RETURNS hafbe_backend.witness
LANGUAGE plpgsql STABLE
SET plan_cache_mode = force_custom_plan
AS
$$
BEGIN
  RETURN (
    WITH limited_set AS (
      SELECT
        cw.witness_id,
        -- Use subquery for single account lookup (see refactoring notes)
        (SELECT av.name FROM hive.accounts_view av WHERE av.id = _witness_id)::TEXT AS witness,
        COALESCE(cw.url, '')                                AS url,
        COALESCE(cw.price_feed, '0.000'::NUMERIC)           AS price_feed,
        COALESCE(cw.bias, 0)                                AS bias,
        COALESCE(cw.feed_updated_at, '1970-01-01 00:00:00'::TIMESTAMP) AS feed_updated_at,
        COALESCE(cw.block_size, 0)                          AS block_size,
        COALESCE(cw.signing_key, '')                        AS signing_key,
        COALESCE(cw.version, '0.0.0')                       AS version,
        COALESCE(cw.missed_blocks, 0)                       AS missed_blocks,
        COALESCE(cw.hbd_interest_rate, 0)                   AS hbd_interest_rate,
        COALESCE(cw.last_created_block_num, 0)              AS last_created_block_num,
        COALESCE(cw.account_creation_fee, 0)                AS account_creation_fee
      FROM hafbe_app.current_witnesses cw
      WHERE cw.witness_id = _witness_id
    )
    SELECT ROW(
      ls.witness,
      a.rank,
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
      ls.account_creation_fee,
      (SELECT vcb.votes_change_breakdown FROM hafbe_backend.witness_votes_change_breakdown(ARRAY[ls.witness_id]) vcb)
    )
    FROM limited_set ls
    JOIN hafbe_app.witness_rank_cache a                 ON a.witness_id = ls.witness_id
    LEFT JOIN hafbe_app.witness_votes_cache all_votes   ON all_votes.witness_id = ls.witness_id
    LEFT JOIN hafbe_app.witness_votes_change_cache wvcc ON wvcc.witness_id = ls.witness_id
  );
END
$$;

-- =============================================================================
-- SECTION 3: Count Functions
-- =============================================================================

/*
 * get_witness_voters_count: Counts total voters for a witness.
 *
 * PARAMETERS:
 *   _witness_id        - Witness account ID
 *   _filter_account_id - Optional: filter to specific voter
 *
 * RETURNS: Count of voters matching criteria
 */
CREATE OR REPLACE FUNCTION hafbe_backend.get_witness_voters_count(
    _witness_id        INT,
    _filter_account_id INT
)
RETURNS INT
LANGUAGE plpgsql STABLE
AS
$$
BEGIN
  RETURN COUNT(*)
  FROM hafbe_backend.current_witness_votes_view
  WHERE
    witness_id = _witness_id AND
    (_filter_account_id IS NULL OR voter_id = _filter_account_id);
END
$$;

/*
 * get_witness_votes_history_count: Counts historical vote records for a witness.
 *
 * PARAMETERS:
 *   _witness_id        - Witness account ID
 *   _filter_account_id - Optional: filter to specific voter
 *   _block_range       - Optional: block range filter
 *
 * RETURNS: Count of vote history records matching criteria
 */
CREATE OR REPLACE FUNCTION hafbe_backend.get_witness_votes_history_count(
    _witness_id        INT,
    _filter_account_id INT,
    _block_range       hive.blocks_range
)
RETURNS INT
LANGUAGE plpgsql STABLE
AS
$$
BEGIN
  RETURN COUNT(*)
  FROM hafbe_backend.witness_votes_history_view
  WHERE
    witness_id = _witness_id AND
    (_block_range.first_block IS NULL OR source_op_block >= _block_range.first_block) AND
    (_block_range.last_block IS NULL  OR source_op_block <= _block_range.last_block) AND
    (_filter_account_id IS NULL       OR voter_id = _filter_account_id);
END
$$;

/*
 * get_witnesses_count: Counts total number of witnesses.
 *
 * RETURNS: Total count of registered witnesses
 */
CREATE OR REPLACE FUNCTION hafbe_backend.get_witnesses_count()
RETURNS INT
LANGUAGE plpgsql STABLE
AS
$$
BEGIN
  RETURN COUNT(*)
  FROM hafbe_app.current_witnesses;
END
$$;

RESET ROLE;
