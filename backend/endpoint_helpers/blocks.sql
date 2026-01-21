SET ROLE hafbe_owner;

/*
 * get_blocks_by_ops: Main orchestrator for block search API.
 *
 * Routes to the appropriate gatherer based on filter parameters, then enriches
 * the results using the shared blocksearch_build_result function.
 *
 * DESIGN:
 *   1. Single CASE statement routes to the appropriate gatherer
 *   2. All gatherers return gatherer_result (intermediate type)
 *   3. blocksearch_build_result handles ALL enrichment (single point of truth)
 *
 * FILTER COMBINATIONS (8 total):
 *   1. no_filter       - No filters
 *   2. single_op       - Single operation type
 *   3. multi_op        - Multiple operation types
 *   4. key_value       - Single op + key-value filter
 *   5. account         - Account only
 *   6. account_op      - Account + single operation
 *   7. account_multi_op - Account + multiple operations
 *   8. account_key_value - Account + single op + key-value
 *
 * PARAMETERS:
 *   _operations  - Array of operation type IDs (NULL = no op filter)
 *   _account     - Account ID (NULL = no account filter)
 *   _order_is    - Sort direction ('asc' or 'desc')
 *   _from        - Starting block (NULL = genesis)
 *   _to          - Ending block (NULL = current head)
 *   _page        - Page number (1-based)
 *   _limit       - Page size
 *   _key_content - Array of values to match for key-value filter
 *   _setof_keys  - JSON array of paths for key-value filter
 *
 * RETURNS: block_history with enriched block data
 */
CREATE OR REPLACE FUNCTION hafbe_backend.get_blocks_by_ops(
    _operations  INT[],
    _account     INT,
    _order_is    hafbe_backend.sort_direction,
    _from        INT,
    _to          INT,
    _page        INT,
    _limit       INT,
    _key_content TEXT[],
    _setof_keys  JSON
)
RETURNS hafbe_backend.block_history
LANGUAGE 'plpgsql' STABLE
AS
$$
DECLARE
  __gathered           hafbe_backend.gatherer_result;
  __filter_by_op       BOOLEAN := (_operations IS NOT NULL);
  __filter_by_single   BOOLEAN := (_operations IS NOT NULL AND array_length(_operations, 1) = 1);
  __filter_by_account  BOOLEAN := (_account IS NOT NULL);
  __filter_by_key      BOOLEAN := (_key_content[1] IS NOT NULL);
BEGIN
  -- Route to appropriate gatherer (single CASE statement)
  __gathered := CASE
    -- 1. No filter
    WHEN NOT __filter_by_op AND NOT __filter_by_account AND NOT __filter_by_key THEN
      hafbe_backend.blocksearch_no_filter(_from, _to, _order_is, _page, _limit)

    -- 2. Single operation only
    WHEN __filter_by_single AND NOT __filter_by_account AND NOT __filter_by_key THEN
      hafbe_backend.blocksearch_single_op(_operations[1], _from, _to, _order_is, _page, _limit)

    -- 3. Multiple operations only
    WHEN __filter_by_op AND NOT __filter_by_single AND NOT __filter_by_account AND NOT __filter_by_key THEN
      hafbe_backend.blocksearch_multi_op(_operations, _from, _to, _order_is, _page, _limit)

    -- 4. Single operation + key-value filter
    WHEN __filter_by_single AND NOT __filter_by_account AND __filter_by_key THEN
      hafbe_backend.blocksearch_key_value(_operations[1], _from, _to, _order_is, _page, _limit, _key_content, _setof_keys)

    -- 5. Account only
    WHEN NOT __filter_by_op AND __filter_by_account AND NOT __filter_by_key THEN
      hafbe_backend.blocksearch_account(_account, _from, _to, _order_is, _page, _limit)

    -- 6. Account + single operation
    WHEN __filter_by_single AND __filter_by_account AND NOT __filter_by_key THEN
      hafbe_backend.blocksearch_account_op(_operations[1], _account, _from, _to, _order_is, _page, _limit)

    -- 7. Account + multiple operations
    WHEN __filter_by_op AND NOT __filter_by_single AND __filter_by_account AND NOT __filter_by_key THEN
      hafbe_backend.blocksearch_account_multi_op(_operations, _account, _from, _to, _order_is, _page, _limit)

    -- 8. Account + single operation + key-value filter
    WHEN __filter_by_single AND __filter_by_account AND __filter_by_key THEN
      hafbe_backend.blocksearch_account_key_value(_operations[1], _account, _from, _to, _order_is, _page, _limit, _key_content, _setof_keys)

    ELSE
      NULL
  END;

  -- Handle invalid parameter combinations
  IF __gathered IS NULL THEN
    RAISE EXCEPTION 'Invalid parameter combination';
  END IF;

  -- Enrich and return (single point of enrichment)
  RETURN hafbe_backend.blocksearch_build_result(__gathered, _order_is);
END
$$;

RESET ROLE;
