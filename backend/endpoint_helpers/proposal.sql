-- =============================================================================
-- Proposal Helper Functions
-- =============================================================================
-- Functions for retrieving proposal-related information including vote history.
-- Supports pagination, voter filtering, and block range filtering.
-- =============================================================================

SET ROLE hafbe_owner;

-- Internal rows carried between page selection and response construction.
-- Keep these separate from both public API types and HAF table row types.
-- The arrays contain only the requested page, in its selected order.
DROP TYPE IF EXISTS hafbe_backend.proposal_listing_page_row CASCADE;
CREATE TYPE hafbe_backend.proposal_listing_page_row AS (
  proposal_id INT,
  creator_id INT,
  receiver_id INT,
  start_date TIMESTAMP,
  end_date TIMESTAMP,
  daily_pay BIGINT,
  subject TEXT,
  permlink TEXT,
  paid_amount BIGINT,
  total_votes BIGINT,
  voters_num INT
);

DROP TYPE IF EXISTS hafbe_backend.proposal_vote_page_row CASCADE;
CREATE TYPE hafbe_backend.proposal_vote_page_row AS (
  voter_id INT,
  proposal_id INT,
  source_op BIGINT,
  creator_id INT,
  receiver_id INT,
  start_date TIMESTAMP,
  end_date TIMESTAMP,
  daily_pay BIGINT,
  subject TEXT,
  permlink TEXT,
  paid_amount BIGINT,
  proxy_account_id INT,
  proxy_id INT
);

DROP TYPE IF EXISTS hafbe_backend.proposal_vote_history_page_row CASCADE;
CREATE TYPE hafbe_backend.proposal_vote_history_page_row AS (
  voter_id INT,
  approve BOOLEAN,
  source_op_block INT
);

-- =============================================================================
-- SECTION 1: Proposal Vote History Functions
-- =============================================================================

/*
 * Proposal vote history carries CURRENT governance stake, not a snapshot from
 * the vote's block. Read the page first, then enrich its voters from the cache
 * and resolve only cache misses through expired_voter_stats_view. Voter names
 * and block timestamps are also resolved for the page rows only: every vote
 * has its voter account and block, so they never decide which rows qualify.
 *
 * A current proxy zeros voter_vests, but preserves direct_vests/proxied_vests.
 * Detect the proxy by its account_id, even when its name is not visible.
 */
DROP FUNCTION IF EXISTS hafbe_backend.get_proposal_votes_history;
CREATE OR REPLACE FUNCTION hafbe_backend.get_proposal_votes_history(
    _proposal_id     INT,
    _filter_account  INT,
    _page            INT,
    _page_size       INT,
    _direction      hafbe_backend.sort_direction,
    _from_block     INT,
    _to_block       INT
)
RETURNS SETOF hafbe_backend.proposal_votes_history_record
LANGUAGE 'plpgsql' STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
SET plan_cache_mode = force_custom_plan
AS
$$
DECLARE
  __offset INT := ((_page - 1) * _page_size);
  _page_rows hafbe_backend.proposal_vote_history_page_row[];
BEGIN
  -- ARRAY preserves this ORDER BY; ordinality below carries the chosen order
  -- through the enrichment joins.
  _page_rows := ARRAY(
    SELECT ROW(
      pvh.voter_id,
      pvh.approve,
      pvh.source_op_block
    )::hafbe_backend.proposal_vote_history_page_row
    FROM hafbe_backend.proposal_votes_history_view pvh
    WHERE
      pvh.proposal_id = _proposal_id AND
      (_filter_account IS NULL OR pvh.voter_id = _filter_account) AND
      (_from_block IS NULL     OR pvh.source_op_block >= _from_block) AND
      (_to_block IS NULL       OR pvh.source_op_block <= _to_block)
    -- A vote and its withdrawal can share a block and voter. source_op is the
    -- final tie-break so pagination retains their chronological order.
    ORDER BY
      (CASE WHEN _direction = 'desc' THEN pvh.source_op_block ELSE NULL END) DESC,
      (CASE WHEN _direction = 'asc'  THEN pvh.source_op_block ELSE NULL END) ASC,
      (CASE WHEN _direction = 'desc' THEN pvh.voter_id        ELSE NULL END) DESC,
      (CASE WHEN _direction = 'asc'  THEN pvh.voter_id        ELSE NULL END) ASC,
      (CASE WHEN _direction = 'desc' THEN pvh.source_op       ELSE NULL END) DESC,
      (CASE WHEN _direction = 'asc'  THEN pvh.source_op       ELSE NULL END) ASC
    OFFSET __offset
    LIMIT _page_size
  );

  RETURN QUERY (
    -- Read each page row's cache entry once. vests is NOT NULL in the cache,
    -- so a NULL here identifies a missing entry rather than a zero balance.
    -- Names and timestamps are per-row LIMIT 1 probes: joining the context
    -- views inflates their estimates and the planner then scans all of them.
    WITH paged_stats AS MATERIALIZED (
      SELECT
        av.name AS voter_name,
        page.voter_id,
        page.approve,
        bv.created_at,
        page.page_order,
        avs.vests,
        avs.account_vests,
        avs.proxied_vests
      FROM unnest(_page_rows) WITH ORDINALITY AS page(
        voter_id, approve, source_op_block, page_order
      )
      CROSS JOIN LATERAL (
        SELECT b.created_at
        FROM hive.blocks_view b
        WHERE b.num = page.source_op_block
        LIMIT 1
      ) bv
      CROSS JOIN LATERAL (
        SELECT a.name
        FROM hive.accounts_view a
        WHERE a.id = page.voter_id
        LIMIT 1
      ) av
      LEFT JOIN hafbe_app.account_vest_stats_cache avs ON avs.account_id = page.voter_id
    ),
    missing_voters AS (
      SELECT DISTINCT ps.voter_id
      FROM paged_stats ps
      WHERE ps.vests IS NULL
    ),
    -- Keep cache misses on the input side of this join. MATERIALIZED prevents
    -- the fallback from being pulled into the response's LEFT JOIN and doing
    -- work for voters already covered by the cache.
    fallback_stats AS MATERIALIZED (
      SELECT
        evs.account_id,
        evs.vests,
        evs.account_vests,
        evs.proxied_vests
      FROM hafbe_backend.expired_voter_stats_view evs
      JOIN missing_voters mv ON mv.voter_id = evs.account_id
    )
    -- Keep the public composite's positional field order and TEXT amounts.
    SELECT
      ps.voter_name::TEXT                                   AS voter_name,
      ps.approve                                            AS approve,
      (CASE
        WHEN cap.account_id IS NOT NULL THEN '0'
        ELSE COALESCE(ps.vests, fs.vests, 0)::TEXT
      END)                                                  AS voter_vests,
      COALESCE(ps.account_vests, fs.account_vests, 0)::TEXT    AS direct_vests,
      COALESCE(ps.proxied_vests, fs.proxied_vests, 0)::TEXT    AS proxied_vests,
      COALESCE(pav.name, '')::TEXT                            AS proxy,
      ps.created_at                                         AS "timestamp"
    FROM paged_stats ps
    LEFT JOIN fallback_stats                   fs  ON fs.account_id  = ps.voter_id
    LEFT JOIN hafbe_app.current_account_proxies cap ON cap.account_id = ps.voter_id
    -- A per-row probe: joining the context view hashes every account.
    LEFT JOIN LATERAL (
      SELECT a.name
      FROM hafbe_app.accounts_view a
      WHERE a.id = cap.proxy_id
      LIMIT 1
    ) pav ON TRUE
    ORDER BY ps.page_order
  );
END
$$;

-- =============================================================================
-- SECTION 2: Count Functions
-- =============================================================================

CREATE OR REPLACE FUNCTION hafbe_backend.get_proposal_votes_history_count(
    _proposal_id       INT,
    _filter_account_id INT,
    _block_range       hive.blocks_range
)
RETURNS INT
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN COUNT(*)
  FROM hafbe_backend.proposal_votes_history_view
  WHERE
    proposal_id = _proposal_id AND
    (_block_range.first_block IS NULL OR source_op_block >= _block_range.first_block) AND
    (_block_range.last_block IS NULL  OR source_op_block <= _block_range.last_block) AND
    (_filter_account_id IS NULL       OR voter_id = _filter_account_id);
END
$$;

-- =============================================================================
-- SECTION 3: Proposal Listing & Active Votes
-- =============================================================================

-- Status is relative to the processed head block, with inclusive start/end.
-- Removed proposals remain stored for history but never match a list filter.
CREATE OR REPLACE FUNCTION hafbe_backend.proposal_status_matches(
    _status     hafbe_backend.proposal_status,
    _start_date TIMESTAMP,
    _end_date   TIMESTAMP,
    _removed    BOOLEAN,
    _now        TIMESTAMP
)
RETURNS BOOLEAN
LANGUAGE 'sql' IMMUTABLE
AS $$
  SELECT NOT _removed AND CASE _status
    WHEN 'all'      THEN TRUE
    WHEN 'active'   THEN _now >= _start_date AND _now <= _end_date
    WHEN 'inactive' THEN _now <  _start_date
    WHEN 'expired'  THEN _now >  _end_date
    WHEN 'votable'  THEN _now <= _end_date
  END;
$$;

/*
 * Count matching proposals without the name or cache joins used by the listing.
 * Keep these filters aligned with eligible_proposals in get_proposals.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.get_proposals_count(
    _status       hafbe_backend.proposal_status,
    _creator_id   INT   DEFAULT NULL,
    _proposal_ids INT[] DEFAULT NULL,
    _voter_id     INT   DEFAULT NULL,
    _search       TEXT  DEFAULT NULL
)
RETURNS INT
LANGUAGE 'plpgsql' STABLE
AS $$
DECLARE
  _now TIMESTAMP := (SELECT created_at FROM hive.blocks_view WHERE num = hafbe_backend.get_hafbe_head_block());
BEGIN
  RETURN COUNT(*)
  FROM hafbe_app.current_proposals cp
  WHERE hafbe_backend.proposal_status_matches(_status, cp.start_date, cp.end_date, cp.removed, _now)
    AND (_creator_id   IS NULL OR cp.creator_id = _creator_id)
    AND (_proposal_ids IS NULL OR cp.proposal_id = ANY(_proposal_ids))
    AND (_search       IS NULL OR cp.subject = _search)
    AND (_voter_id     IS NULL OR EXISTS (
          SELECT 1 FROM hafbe_app.current_proposal_votes cpv
          WHERE cpv.proposal_id = cp.proposal_id AND cpv.voter_id = _voter_id
        ));
END $$;

/*
 * Select the proposal page, collect its account IDs, then resolve display names.
 * Creator names and vote totals participate in selection because they are sort
 * keys. The inner creator lookup also determines eligibility for every sort mode;
 * moving it after pagination would change pages when a name is missing. It is a
 * per-row LIMIT 1 probe: joining the context view inflates its estimate and the
 * planner then hashes every account.
 *
 * The page carries proposal metadata and cached totals into the final SELECT.
 * paid_amount comes from current_proposals; payments need no per-request sum.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.get_proposals(
    _status       hafbe_backend.proposal_status,
    _page         INT,
    _page_size    INT,
    _sort         hafbe_backend.order_by_proposal,
    _direction    hafbe_backend.sort_direction,
    _creator_id   INT   DEFAULT NULL,
    _proposal_ids INT[] DEFAULT NULL,
    _voter_id     INT   DEFAULT NULL,
    _search       TEXT  DEFAULT NULL
)
RETURNS SETOF hafbe_backend.proposal
LANGUAGE 'plpgsql' STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
-- Custom plans resolve the CASE sort keys and see the account ID array below.
SET plan_cache_mode = force_custom_plan
AS $$
DECLARE
  __page_proposals hafbe_backend.proposal_listing_page_row[];
  __account_ids INT[];
  __offset INT := ((_page - 1) * _page_size);
  _now TIMESTAMP := (SELECT created_at FROM hive.blocks_view WHERE num = hafbe_backend.get_hafbe_head_block());
BEGIN
  -- Select the page with the original filters, creator eligibility and sort keys.
  -- Do not deduplicate page rows: each visible creator match participates.
  __page_proposals := ARRAY(
    WITH eligible_proposals AS (
      SELECT
        cp.proposal_id, cp.creator_id, cp.receiver_id,
        cp.start_date, cp.end_date, cp.daily_pay,
        cp.subject, cp.permlink, cp.paid_amount
      FROM hafbe_app.current_proposals cp
      WHERE hafbe_backend.proposal_status_matches(_status, cp.start_date, cp.end_date, cp.removed, _now)
        AND (_creator_id   IS NULL OR cp.creator_id = _creator_id)
        AND (_proposal_ids IS NULL OR cp.proposal_id = ANY(_proposal_ids))
        AND (_search       IS NULL OR cp.subject = _search)
        AND (_voter_id     IS NULL OR EXISTS (
              SELECT 1 FROM hafbe_app.current_proposal_votes cpv
              WHERE cpv.proposal_id = cp.proposal_id AND cpv.voter_id = _voter_id
            ))
    ),
    sortable_proposals AS (
      SELECT
        ep.*,
        av.name AS creator_name,
        COALESCE(vsc.total_votes, 0) AS total_votes,
        COALESCE(vsc.voters_num, 0) AS voters_num
      FROM eligible_proposals ep
      CROSS JOIN LATERAL (
        SELECT a.name
        FROM hafbe_app.accounts_view a
        WHERE a.id = ep.creator_id
        LIMIT 1
      ) av
      LEFT JOIN hafbe_app.proposal_vote_stats_cache vsc ON vsc.proposal_id = ep.proposal_id
    )
    SELECT ROW(
      sp.proposal_id, sp.creator_id, sp.receiver_id,
      sp.start_date, sp.end_date, sp.daily_pay,
      sp.subject, sp.permlink, sp.paid_amount,
      sp.total_votes, sp.voters_num
    )::hafbe_backend.proposal_listing_page_row
    FROM sortable_proposals sp
    ORDER BY
      (CASE WHEN _sort = 'by_creator'     AND _direction = 'asc'  THEN sp.creator_name END) ASC,
      (CASE WHEN _sort = 'by_creator'     AND _direction = 'desc' THEN sp.creator_name END) DESC,
      (CASE WHEN _sort = 'by_start_date'  AND _direction = 'asc'  THEN sp.start_date   END) ASC,
      (CASE WHEN _sort = 'by_start_date'  AND _direction = 'desc' THEN sp.start_date   END) DESC,
      (CASE WHEN _sort = 'by_end_date'    AND _direction = 'asc'  THEN sp.end_date     END) ASC,
      (CASE WHEN _sort = 'by_end_date'    AND _direction = 'desc' THEN sp.end_date     END) DESC,
      (CASE WHEN _sort = 'by_total_votes' AND _direction = 'asc'  THEN sp.total_votes  END) ASC,
      (CASE WHEN _sort = 'by_total_votes' AND _direction = 'desc' THEN sp.total_votes  END) DESC,
      (CASE WHEN _direction = 'asc'  THEN sp.proposal_id END) ASC,
      (CASE WHEN _direction = 'desc' THEN sp.proposal_id END) DESC
    OFFSET __offset
    LIMIT _page_size
  );

  -- Deduplicate only lookup IDs, retaining every matching row in accounts_view.
  -- This separate statement supplies the next custom plan with the actual IDs.
  __account_ids := ARRAY(
    SELECT p.creator_id FROM unnest(__page_proposals) p
    UNION
    SELECT p.receiver_id FROM unnest(__page_proposals) p
  );

  RETURN QUERY (
    WITH account_names AS MATERIALIZED (
      SELECT av.id, av.name
      FROM hafbe_app.accounts_view av
      WHERE av.id = ANY(__account_ids)
    )
    SELECT
      p.proposal_id AS id,
      p.proposal_id,
      cav.name::TEXT AS creator,
      rav.name::TEXT AS receiver,
      p.start_date,
      p.end_date,
      p.daily_pay::TEXT,
      p.subject,
      p.permlink,
      p.total_votes::TEXT,
      p.voters_num,
      p.paid_amount::TEXT,
      (CASE
        WHEN _now > p.end_date   THEN 'expired'
        WHEN _now < p.start_date THEN 'inactive'
        ELSE                         'active'
      END)::TEXT AS status
    FROM unnest(__page_proposals) p
    JOIN account_names cav ON cav.id = p.creator_id
    JOIN account_names rav ON rav.id = p.receiver_id
    -- Resolve creators again as before: multiple visible names multiply results.
    -- Page ordinality alone cannot order those names across proposals, so retain
    -- the listing's final sort, including the proposal ID tie-break in both orders.
    ORDER BY
      (CASE WHEN _sort = 'by_creator'     AND _direction = 'asc'  THEN cav.name      END) ASC,
      (CASE WHEN _sort = 'by_creator'     AND _direction = 'desc' THEN cav.name      END) DESC,
      (CASE WHEN _sort = 'by_start_date'  AND _direction = 'asc'  THEN p.start_date  END) ASC,
      (CASE WHEN _sort = 'by_start_date'  AND _direction = 'desc' THEN p.start_date  END) DESC,
      (CASE WHEN _sort = 'by_end_date'    AND _direction = 'asc'  THEN p.end_date    END) ASC,
      (CASE WHEN _sort = 'by_end_date'    AND _direction = 'desc' THEN p.end_date    END) DESC,
      (CASE WHEN _sort = 'by_total_votes' AND _direction = 'asc'  THEN p.total_votes END) ASC,
      (CASE WHEN _sort = 'by_total_votes' AND _direction = 'desc' THEN p.total_votes END) DESC,
      (CASE WHEN _direction = 'asc'  THEN p.proposal_id END) ASC,
      (CASE WHEN _direction = 'desc' THEN p.proposal_id END) DESC
  );
END $$;

-- =============================================================================
-- SECTION 4: Proposal Votes Listing
-- =============================================================================

-- Count matching approvals without fetching response names or statistics.
-- Status always describes the proposal, not the vote itself.
CREATE OR REPLACE FUNCTION hafbe_backend.get_proposal_votes_count(
    _status      hafbe_backend.proposal_status,
    _proposal_id INT DEFAULT NULL,
    _voter_id    INT DEFAULT NULL
)
RETURNS INT
LANGUAGE 'plpgsql' STABLE
AS $$
DECLARE
  _now TIMESTAMP := (SELECT created_at FROM hive.blocks_view WHERE num = hafbe_backend.get_hafbe_head_block());
BEGIN
  RETURN COUNT(*)
  FROM hafbe_app.current_proposal_votes cpv
  JOIN hafbe_app.current_proposals cp ON cp.proposal_id = cpv.proposal_id
  WHERE hafbe_backend.proposal_status_matches(_status, cp.start_date, cp.end_date, cp.removed, _now)
    AND (_proposal_id IS NULL OR cpv.proposal_id = _proposal_id)
    AND (_voter_id    IS NULL OR cpv.voter_id = _voter_id);
END $$;

-- Current approvals: select an ordered page, resolve its names, render it.
-- Unlike history, a missing vest cache row yields zero without a fallback.
CREATE OR REPLACE FUNCTION hafbe_backend.get_proposal_votes(
    _status      hafbe_backend.proposal_status,
    _page        INT,
    _page_size   INT,
    _sort        hafbe_backend.order_by_proposal_vote,
    _direction   hafbe_backend.sort_direction,
    _proposal_id INT DEFAULT NULL,
    _voter_id    INT DEFAULT NULL
)
RETURNS SETOF hafbe_backend.proposal_vote
LANGUAGE 'plpgsql' STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
-- Plan both the selected sort and the subsequent lookup using actual page IDs.
SET plan_cache_mode = force_custom_plan
AS $$
DECLARE
  __selected_votes hafbe_app.current_proposal_votes[];
  __page_votes hafbe_backend.proposal_vote_page_row[];
  __account_ids INT[];
  __offset INT := ((_page - 1) * _page_size);
  _now TIMESTAMP := (SELECT created_at FROM hive.blocks_view WHERE num = hafbe_backend.get_hafbe_head_block());
BEGIN
  -- Select only vote rows here. Proposal status determines eligibility, but
  -- fetching response metadata or proxies before OFFSET would also enrich
  -- every skipped vote on a deep page.
  __selected_votes := ARRAY(
    SELECT cpv
    FROM hafbe_app.current_proposal_votes cpv
    JOIN hafbe_app.current_proposals cp ON cp.proposal_id = cpv.proposal_id
    WHERE hafbe_backend.proposal_status_matches(_status, cp.start_date, cp.end_date, cp.removed, _now)
      AND (_proposal_id IS NULL OR cpv.proposal_id = _proposal_id)
      AND (_voter_id    IS NULL OR cpv.voter_id = _voter_id)
    ORDER BY
      (CASE WHEN _sort = 'by_voter_proposal' AND _direction = 'asc'  THEN cpv.voter_id    END) ASC,
      (CASE WHEN _sort = 'by_voter_proposal' AND _direction = 'desc' THEN cpv.voter_id    END) DESC,
      (CASE WHEN _sort = 'by_voter_proposal' AND _direction = 'asc'  THEN cpv.proposal_id END) ASC,
      (CASE WHEN _sort = 'by_voter_proposal' AND _direction = 'desc' THEN cpv.proposal_id END) DESC,
      (CASE WHEN _sort = 'by_proposal_voter' AND _direction = 'asc'  THEN cpv.proposal_id END) ASC,
      (CASE WHEN _sort = 'by_proposal_voter' AND _direction = 'desc' THEN cpv.proposal_id END) DESC,
      (CASE WHEN _sort = 'by_proposal_voter' AND _direction = 'asc'  THEN cpv.voter_id    END) ASC,
      (CASE WHEN _sort = 'by_proposal_voter' AND _direction = 'desc' THEN cpv.voter_id    END) DESC
    OFFSET __offset
    LIMIT _page_size
  );

  -- Fetch metadata and proxy presence once, only for the selected page.
  -- Both tables have unique join keys, preserving one row per selected vote.
  __page_votes := ARRAY(
    SELECT ROW(
      selected.voter_id, selected.proposal_id, selected.source_op,
      cp.creator_id, cp.receiver_id, cp.start_date, cp.end_date,
      cp.daily_pay, cp.subject, cp.permlink, cp.paid_amount,
      cap.account_id, cap.proxy_id
    )::hafbe_backend.proposal_vote_page_row
    FROM unnest(__selected_votes) WITH ORDINALITY selected
    JOIN hafbe_app.current_proposals cp ON cp.proposal_id = selected.proposal_id
    LEFT JOIN hafbe_app.current_account_proxies cap ON cap.account_id = selected.voter_id
    ORDER BY selected.ordinality
  );

  -- Materialize the requested IDs as a PL/pgSQL value before the name lookup.
  -- A subquery inside ANY would hide the actual page IDs from the planner.
  __account_ids := ARRAY(
    SELECT voter_id FROM unnest(__page_votes)
    UNION
    SELECT creator_id FROM unnest(__page_votes)
    UNION
    SELECT receiver_id FROM unnest(__page_votes)
    UNION
    SELECT proxy_id FROM unnest(__page_votes) WHERE proxy_id IS NOT NULL
  );

  RETURN QUERY
  WITH page_votes AS MATERIALIZED (
    -- Separate page expansion from name joins and the final ordering. Joining
    -- directly to ordered unnest can favor repeated name scans to avoid a sort.
    SELECT * FROM unnest(__page_votes) WITH ORDINALITY
  ),
  account_names AS MATERIALIZED (
    SELECT av.id, av.name
    FROM hafbe_app.accounts_view av
    WHERE av.id = ANY (__account_ids)
  )
  SELECT
    av.name::TEXT AS voter_name,
    ROW(
      pv.proposal_id,
      pv.proposal_id,
      cav.name::TEXT,
      rav.name::TEXT,
      pv.start_date,
      pv.end_date,
      pv.daily_pay::TEXT,
      pv.subject,
      pv.permlink,
      COALESCE(vsc.total_votes, 0)::TEXT,
      COALESCE(vsc.voters_num, 0),
      pv.paid_amount::TEXT,
      (CASE
        WHEN _now > pv.end_date   THEN 'expired'
        WHEN _now < pv.start_date THEN 'inactive'
        ELSE                          'active'
      END)::TEXT
    )::hafbe_backend.proposal AS proposal,
    -- Proxy presence zeroes voting power even if its name is not visible.
    (CASE
      WHEN pv.proxy_account_id IS NOT NULL THEN '0'
      ELSE COALESCE(avs.vests, 0)::TEXT
    END) AS voter_vests,
    COALESCE(avs.account_vests, 0)::TEXT AS direct_vests,
    COALESCE(avs.proxied_vests, 0)::TEXT AS proxied_vests,
    COALESCE(pav.name, '')::TEXT AS proxy,
    bv.created_at AS "timestamp"
  FROM page_votes pv
  JOIN account_names av ON av.id = pv.voter_id
  JOIN account_names cav ON cav.id = pv.creator_id
  JOIN account_names rav ON rav.id = pv.receiver_id
  LEFT JOIN account_names pav ON pav.id = pv.proxy_id
  LEFT JOIN hafbe_app.proposal_vote_stats_cache vsc ON vsc.proposal_id = pv.proposal_id
  LEFT JOIN hafbe_app.account_vest_stats_cache avs ON avs.account_id = pv.voter_id
  JOIN hive.blocks_view bv ON bv.num = hafd.operation_id_to_block_num(pv.source_op)
  ORDER BY pv.ordinality;
END $$;

RESET ROLE;
