-- =============================================================================
-- Proposal Helper Functions
-- =============================================================================
-- Functions for retrieving proposal-related information including vote history.
-- Supports pagination, voter filtering, and block range filtering.
-- =============================================================================

SET ROLE hafbe_owner;

-- =============================================================================
-- SECTION 1: Proposal Vote History Functions
-- =============================================================================

/*
 * get_proposal_votes_history: Gets historical voting records for a proposal.
 *
 * Returns vote history including both approve and unapprove actions against a
 * given proposal. Unlike witness votes, proposal vote history does not carry
 * vest/voting-power stats — it is a pure (voter, approve, timestamp) stream.
 *
 * PARAMETERS:
 *   proposal_id    - Proposal id to get vote history for
 *   filter_account - Optional: filter to a specific voter account id
 *   page           - Page number (1-based)
 *   page-size      - Number of records per page
 *   direction      - Sort direction: 'asc' or 'desc' (by block)
 *   from-block     - Optional: lower block bound (inclusive)
 *   to-block       - Optional: upper block bound (inclusive)
 *
 * RETURNS: Set of proposal_votes_history_record with voter name, approve flag
 *          and block timestamp.
 */
DROP FUNCTION IF EXISTS hafbe_backend.get_proposal_votes_history;
CREATE OR REPLACE FUNCTION hafbe_backend.get_proposal_votes_history(
    _proposal_id     INT,
    _filter_account  INT,
    _page            INT,
    _page_size       INT,
    _direction       hafbe_backend.sort_direction,
    _from_block      INT,
    _to_block        INT
)
RETURNS SETOF hafbe_backend.proposal_votes_history_record
LANGUAGE 'plpgsql' STABLE
SET plan_cache_mode = force_custom_plan
AS
$$
DECLARE
  __offset INT := ((_page - 1) * _page_size);
BEGIN
  RETURN QUERY (
    WITH limited_set AS MATERIALIZED (
      SELECT
        av.name,
        pvh.voter_id,
        pvh.approve,
        pvh.source_op_block,
        bv.created_at
      FROM hafbe_backend.proposal_votes_history_view pvh
      JOIN hive.blocks_view bv   ON bv.num = pvh.source_op_block
      JOIN hive.accounts_view av ON av.id = pvh.voter_id
      WHERE
        pvh.proposal_id = _proposal_id AND
        (_filter_account IS NULL OR pvh.voter_id = _filter_account) AND
        (_from_block IS NULL     OR pvh.source_op_block >= _from_block) AND
        (_to_block IS NULL       OR pvh.source_op_block <= _to_block)
      ORDER BY
        (CASE WHEN _direction = 'desc' THEN pvh.source_op_block ELSE NULL END) DESC,
        (CASE WHEN _direction = 'asc'  THEN pvh.source_op_block ELSE NULL END) ASC,
        (CASE WHEN _direction = 'desc' THEN pvh.voter_id        ELSE NULL END) DESC,
        (CASE WHEN _direction = 'asc'  THEN pvh.voter_id        ELSE NULL END) ASC
      OFFSET __offset
      LIMIT _page_size
    )
    SELECT
      ls.name::TEXT,
      ls.approve,
      ls.created_at
    FROM limited_set ls
  );
END
$$;

-- =============================================================================
-- SECTION 2: Count Functions
-- =============================================================================

/*
 * get_proposal_votes_history_count: Counts historical vote records for a proposal.
 *
 * PARAMETERS:
 *   _proposal_id       - Proposal id
 *   _filter_account_id - Optional: filter to a specific voter account id
 *   _block_range       - Optional: block range filter
 *
 * RETURNS: Count of vote history records matching criteria
 */
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

RESET ROLE;
