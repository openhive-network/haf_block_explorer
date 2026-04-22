-- =============================================================================
-- Proxy Helper Functions
-- =============================================================================
-- Functions for retrieving account proxy information and voting power.
-- =============================================================================

SET ROLE hafbe_owner;

/*
 * get_account_proxies_power: Retrieves accounts that have delegated their voting
 * power to the specified proxy account.
 *
 * Returns paginated list of delegating accounts with their effective voting power,
 * calculated as: account_vests - delayed_vests + proxied_vests
 *
 * PARAMETERS:
 *   _account_id - The proxy account ID to find delegators for
 *   _page       - Page number (1-based, default: 1)
 *   _sort       - Sort field: 'account', 'proxy_date', 'proxied_vests'
 *   _direction  - Sort direction: 'asc' or 'desc'
 *
 * RETURNS: Set of proxy_power records with delegator name, timestamp, and vests
 */
DROP FUNCTION IF EXISTS hafbe_backend.get_account_proxies_power;
CREATE OR REPLACE FUNCTION hafbe_backend.get_account_proxies_power(
    _account_id INT,
    _page       INT DEFAULT 1,
    _sort       hafbe_backend.order_by_proxy DEFAULT 'proxy_date',
    _direction  hafbe_backend.sort_direction DEFAULT 'desc'
)
RETURNS SETOF hafbe_backend.proxy_power
LANGUAGE 'plpgsql' STABLE
SET plan_cache_mode = force_custom_plan
AS
$$
DECLARE
  __nai_vests     INT := btracker_backend.nai_vests();
  __max_page_size INT := hafbe_backend.default_max_page_size();
BEGIN
  RETURN QUERY
    /*
     * =========================================================================
     * CTE: scored
     * =========================================================================
     * PURPOSE: Compute effective voting power for every delegator of the
     * target proxy. We need the full set before we can sort by proxied_vests
     * or account name across pages.
     *
     * NOTE: Pagination is applied AFTER the sort (in limited_set) so results
     * remain stable when the user pages through amount-sorted data.
     */
    WITH scored AS (
      SELECT
        cap.source_op,
        av.name,
        bv.created_at,
        (
          COALESCE(cab.balance, 0) - COALESCE(aw.delayed_vests, 0) + COALESCE(avs.proxied_vests, 0)
        ) AS vests
      FROM hafbe_backend.current_account_proxies_view cap
      JOIN hive.accounts_view av                                   ON av.id = cap.account_id
      JOIN hive.blocks_view bv                                     ON bv.num = cap.source_op_block
      LEFT JOIN current_account_balances cab                       ON cab.account = cap.account_id AND cab.nai = __nai_vests
      LEFT JOIN account_withdraws aw                               ON aw.account = cap.account_id
      LEFT JOIN hafbe_backend.voters_proxied_vests_sum_view avs    ON avs.proxy_id = cap.account_id
      WHERE cap.proxy_id = _account_id
    ),
    /*
     * DYNAMIC SORT:
     *   Uses CASE expressions to enable sorting by different columns.
     *   Each sort field has ASC and DESC variants. Only one CASE matches
     *   per row; others return NULL and are ignored.
     */
    limited_set AS (
      SELECT *
      FROM scored s
      ORDER BY
        -- Sort by delegator account name
        (CASE WHEN _direction = 'desc' AND _sort = 'account'       THEN s.name           ELSE NULL END) DESC,
        (CASE WHEN _direction = 'asc'  AND _sort = 'account'       THEN s.name           ELSE NULL END) ASC,
        -- Sort by effective vested amount proxied to _account_id
        (CASE WHEN _direction = 'desc' AND _sort = 'proxied_vests' THEN s.vests          ELSE NULL END) DESC,
        (CASE WHEN _direction = 'asc'  AND _sort = 'proxied_vests' THEN s.vests          ELSE NULL END) ASC,
        -- Sort by the block at which the proxy was set (stand-in for proxy_date)
        (CASE WHEN _direction = 'desc' AND _sort = 'proxy_date'    THEN s.source_op      ELSE NULL END) DESC,
        (CASE WHEN _direction = 'asc'  AND _sort = 'proxy_date'    THEN s.source_op      ELSE NULL END) ASC,
        -- Tiebreaker: source_op for stable ordering
        (CASE WHEN _direction = 'desc'                             THEN s.source_op      ELSE NULL END) DESC,
        (CASE WHEN _direction = 'asc'                              THEN s.source_op      ELSE NULL END) ASC
      LIMIT  __max_page_size
      OFFSET (_page - 1) * __max_page_size
    )
    SELECT
      ls.name::TEXT,
      ls.created_at,
      -- Cast to TEXT so large VESTS values are not mangled by JSON serialization
      ls.vests::TEXT
    FROM limited_set ls;
END
$$;

RESET ROLE;
