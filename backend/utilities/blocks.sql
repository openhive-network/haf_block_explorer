SET ROLE hafbe_owner;

-- ============================================================================
-- Block Information Utilities
-- ============================================================================
-- Functions for retrieving block-related information from the HAF database.
-- These provide a single source of truth for querying the current state of
-- both HAF (blockchain data) and HAFBE (application data).
--
-- USAGE:
--   - get_haf_head_block(): For determining how much blockchain data is available
--   - get_hafbe_head_block(): For determining how much HAFBE has processed
-- ============================================================================

/*
 * get_haf_head_block: Returns the highest block number available in HAF.
 *
 * This represents the most recent block that has been synced from the blockchain
 * into the HAF database. Use this to determine the upper bound of available data.
 *
 * RETURNS: The highest block number in hive.blocks_view
 *
 * NOTE: This queries the blockchain data (HAF), not the HAFBE application state.
 *       To check HAFBE processing progress, use get_hafbe_head_block() instead.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.get_haf_head_block()
RETURNS INT -- noqa: LT01, CP05
LANGUAGE 'plpgsql'
STABLE
AS
$$
BEGIN
  RETURN bv.num FROM hive.blocks_view bv ORDER BY bv.num DESC LIMIT 1;
END
$$;

/*
 * get_hafbe_head_block: Returns the highest block number processed by HAFBE.
 *
 * This represents the most recent block that HAFBE has finished processing.
 * There may be a gap between this and get_haf_head_block() if HAFBE is still
 * catching up to the blockchain.
 *
 * RETURNS: The current_block_num from the hafbe_app context
 *
 * USAGE: Use this to determine what data is available in HAFBE tables.
 *        API endpoints should use this to bound their queries.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.get_hafbe_head_block()
RETURNS INT -- noqa: LT01, CP05
LANGUAGE 'plpgsql'
STABLE
AS
$$
BEGIN
  RETURN current_block_num FROM hafd.contexts WHERE name = 'hafbe_app';
END
$$;

RESET ROLE;
