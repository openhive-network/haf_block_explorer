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
 *
 * RETURNS: Set of proxy_power records with delegator name, timestamp, and vests
 */
CREATE OR REPLACE FUNCTION hafbe_backend.get_account_proxies_power(
    _account_id INT,
    _page       INT DEFAULT 1
)
RETURNS SETOF hafbe_backend.proxy_power
LANGUAGE 'plpgsql' STABLE
AS
$$
DECLARE
  __nai_vests     INT := btracker_backend.nai_vests();
  __max_page_size INT := hafbe_backend.default_max_page_size();
BEGIN
  RETURN QUERY
    /*
     * =========================================================================
     * CTE: delegates
     * =========================================================================
     * WHY MATERIALIZED: Pagination must be applied before JOINs to minimize
     * the number of rows processed in subsequent operations.
     *
     * PURPOSE: Find all accounts that have set the target account as their proxy.
     *
     * DATA FLOW:
     *   1. Filter current_account_proxies_view for target proxy
     *   2. Order by source_op DESC (most recent delegations first)
     *   3. Apply pagination BEFORE joining to other tables
     */
    WITH delegates AS MATERIALIZED (
      SELECT
        cap.account_id,
        cap.source_op,
        cap.source_op_block  -- block_num extracted from operation id
      FROM hafbe_backend.current_account_proxies_view cap
      WHERE cap.proxy_id = _account_id
      ORDER BY cap.source_op DESC
      LIMIT  __max_page_size
      OFFSET (_page - 1) * __max_page_size
    )
    SELECT
      av.name::TEXT,
      bv.created_at,
      /*
       * EFFECTIVE VOTING POWER CALCULATION:
       *   account_vests - delayed_vests + proxied_vests
       *
       * - account_vests: Raw VESTS balance from balance tracker
       * - delayed_vests: Vests currently powering down (not available for voting)
       * - proxied_vests: Vests delegated TO this account by others
       *
       * Note: Values cast to TEXT because large VESTS values can be
       * compressed incorrectly by JSON serialization.
       */
      (
        COALESCE(cab.balance, 0) - COALESCE(aw.delayed_vests, 0) + COALESCE(avs.proxied_vests, 0)
      )::TEXT
    FROM delegates d
    -- Use hive views for API-facing functions
    JOIN hive.accounts_view av                                   ON av.id = d.account_id
    JOIN hive.blocks_view bv                                     ON bv.num = d.source_op_block
    -- Balance data (VESTS)
    LEFT JOIN current_account_balances cab                       ON cab.account = d.account_id AND cab.nai = __nai_vests
    -- Delayed vests from active power-downs
    LEFT JOIN account_withdraws aw                               ON aw.account = d.account_id
    -- Pre-aggregated proxied vests sum
    LEFT JOIN hafbe_backend.voters_proxied_vests_sum_view avs    ON avs.proxy_id = d.account_id
    -- Re-apply order after JOINs to maintain pagination consistency
    ORDER BY d.source_op DESC;
END
$$;

RESET ROLE;
