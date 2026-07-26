SET ROLE hafbe_owner;

-- ============================================================================
-- Block Search Composite Types
-- ============================================================================
-- Composite types used to return bundled block-search results.
--
-- WHY THESE LIVE IN THEIR OWN FILE
--   Re-creating a composite type requires DROP TYPE ... CASCADE, and CASCADE also
--   removes every function that merely *returns* it. hafbe_backend.gatherer_result is
--   returned by the eight gatherers in backend/endpoint_helpers/blocksearch_filters.sql,
--   which used to be collateral damage whenever backend/utilities/blocksearch.sql was
--   re-applied on its own: a full install_app.sh run re-creates the gatherers afterwards
--   and self-heals, so CI never saw it, but a partial hot-patch of just the changed files
--   left /block-search answering HTTP 500 on every variant.
--
--   Keeping the types here -- applied before both blocksearch.sql and
--   blocksearch_filters.sql -- means re-applying the *function* files never drops a type,
--   so the dependents survive. Same reasoning as the note in
--   backend/endpoint_helpers/transactions.sql.
--
--   If you change a type in this file you MUST also re-apply
--   backend/endpoint_helpers/blocksearch_filters.sql and backend/endpoint_helpers/blocks.sql.
--
-- DEPENDS ON: hafbe_backend.block_operations (endpoints/types/blocks.sql)
-- ============================================================================

/*
 * blocksearch_filter_return: Return type for block search filter functions.
 *
 * FIELDS:
 *   count_blocks - Total number of blocks matching the filter (NULL if not counted)
 *   from_block   - Starting block number of the range
 *   to_block     - Ending block number of the range
 */
DROP TYPE IF EXISTS hafbe_backend.blocksearch_filter_return CASCADE;
CREATE TYPE hafbe_backend.blocksearch_filter_return AS (
  count_blocks INT,
  from_block   INT,
  to_block     INT
);

/*
 * blocksearch_account_filter_return: Return type for account-based block searches.
 *
 * FIELDS:
 *   from_block - Starting block number of the range
 *   to_block   - Ending block number of the range
 *   from_seq   - Starting account operation sequence number
 *   to_seq     - Ending account operation sequence number
 */
DROP TYPE IF EXISTS hafbe_backend.blocksearch_account_filter_return CASCADE;
CREATE TYPE hafbe_backend.blocksearch_account_filter_return AS (
  from_block INT,
  to_block   INT,
  from_seq   INT,
  to_seq     INT
);

/*
 * calculate_pages_return: Return type for pagination calculations.
 *
 * FIELDS:
 *   rest_of_division - Remainder when dividing total by page size
 *   total_pages      - Total number of pages available
 *   page_num         - Adjusted page number for the query
 *   offset_filter    - SQL OFFSET value for the query
 *   limit_filter     - SQL LIMIT value for the query
 */
DROP TYPE IF EXISTS hafbe_backend.calculate_pages_return CASCADE;
CREATE TYPE hafbe_backend.calculate_pages_return AS (
  rest_of_division INT,
  total_pages      INT,
  page_num         INT,
  offset_filter    INT,
  limit_filter     INT
);

/*
 * find_blocks_with_op_return: Return type for operation-based block searches.
 *
 * FIELDS:
 *   block_num  - Block number where the operation was found
 *   op_type_id - Operation type ID
 *   op_count   - Number of operations of this type in the block (NULL for account searches)
 */
DROP TYPE IF EXISTS hafbe_backend.find_blocks_with_op_return CASCADE;
CREATE TYPE hafbe_backend.find_blocks_with_op_return AS (
  block_num  INT,
  op_type_id INT,
  op_count   INT
);

/*
 * gathered_block: Intermediate block representation for gatherer functions.
 *
 * FIELDS:
 *   block_num  - Block number
 *   operations - Array of operation counts for this block
 *
 * USAGE: Used by gatherer functions to pass block data to the finalize step
 *        before enrichment with metadata (hash, prev, producer_account, etc.)
 */
DROP TYPE IF EXISTS hafbe_backend.gathered_block CASCADE;
CREATE TYPE hafbe_backend.gathered_block AS (
  block_num  INT,
  operations hafbe_backend.block_operations[]
);

/*
 * gatherer_result: Return type for all block search gatherer functions.
 *
 * FIELDS:
 *   blocks            - Array of (block_num, operations) tuples, paginated and ordered
 *   total_count       - Total number of blocks matching the filter (may be capped)
 *   total_pages       - Total number of pages available
 *   min_block_num     - Minimum block number found (for cursor calculation)
 *   pre_grouped_count - Count of operations before grouping (for cursor saturation check)
 *   max_page_limit    - __max_page_count * _limit (for cursor saturation check)
 *   range_from        - Normalized start of block range
 *   range_to          - Normalized end of block range
 *
 * CURSOR LOGIC:
 *   The cursor_from value is calculated by blocksearch_build_result using:
 *   - If min_block_num IS NULL: no results, cursor = range_from
 *   - If min_block_num = 1: at genesis, cursor = 1
 *   - If pre_grouped_count != max_page_limit: not saturated, cursor = range_from
 *   - Otherwise: saturated results, cursor = min_block_num - 1
 */
DROP TYPE IF EXISTS hafbe_backend.gatherer_result CASCADE;
CREATE TYPE hafbe_backend.gatherer_result AS (
  blocks            hafbe_backend.gathered_block[],
  total_count       INT,
  total_pages       INT,
  min_block_num     INT,
  pre_grouped_count INT,
  max_page_limit    INT,
  range_from        INT,
  range_to          INT
);

RESET ROLE;
