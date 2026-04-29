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
  __max_page_size INT := hafbe_backend.default_max_page_size();
  __offset        INT := (_page - 1) * __max_page_size;
BEGIN
  _sort      := COALESCE(_sort, 'proxy_date');
  _direction := COALESCE(_direction, 'desc');
  /*
   * =============================================================================
   * FAST PATH: sort = 'proxy_date' (the default, and by far the hottest case)
   * =============================================================================
   * source_op is already in current_account_proxies_view, so we can order +
   * paginate BEFORE joining. That limits downstream joins to one page of rows
   * instead of every delegator of this proxy — O(page_size) vs O(N).
   */
  IF _sort = 'proxy_date' THEN
    RETURN QUERY
      WITH delegates AS MATERIALIZED (
        SELECT cap.account_id, cap.source_op, cap.source_op_block
        FROM hafbe_backend.current_account_proxies_view cap
        WHERE cap.proxy_id = _account_id
        ORDER BY
          (CASE WHEN _direction = 'desc' THEN cap.source_op ELSE NULL END) DESC,
          (CASE WHEN _direction = 'asc'  THEN cap.source_op ELSE NULL END) ASC
        LIMIT  __max_page_size
        OFFSET __offset
      )
      SELECT
        av.name::TEXT,
        bv.created_at,
        COALESCE(avs.vests, 0)::TEXT
      FROM delegates d
      JOIN hive.accounts_view av                       ON av.id = d.account_id
      JOIN hive.blocks_view bv                         ON bv.num = d.source_op_block
      LEFT JOIN hafbe_app.account_vest_stats_cache avs ON avs.account_id = d.account_id
      ORDER BY
        (CASE WHEN _direction = 'desc' THEN d.source_op ELSE NULL END) DESC,
        (CASE WHEN _direction = 'asc'  THEN d.source_op ELSE NULL END) ASC;
    RETURN;
  END IF;

  /*
   * =============================================================================
   * GENERAL PATH: sort by 'account' or 'proxied_vests'
   * =============================================================================
   * Sort key (name, vests) is only known after joins, so we must materialize
   * the full delegator set before sorting/paginating.
   *
   * Vests come from hafbe_app.account_vest_stats_cache (refreshed every block
   * by process_witness_votes_cache), which now covers proxy setters, so this
   * path still only does one PK lookup per row.
   */
  RETURN QUERY
    WITH scored AS (
      SELECT
        cap.source_op,
        av.name,
        bv.created_at,
        COALESCE(avs.vests, 0) AS vests
      FROM hafbe_backend.current_account_proxies_view cap
      JOIN hive.accounts_view av                       ON av.id = cap.account_id
      JOIN hive.blocks_view bv                         ON bv.num = cap.source_op_block
      LEFT JOIN hafbe_app.account_vest_stats_cache avs ON avs.account_id = cap.account_id
      WHERE cap.proxy_id = _account_id
    ),
    limited_set AS (
      SELECT *
      FROM scored s
      ORDER BY
        -- Sort by delegator account name
        (CASE WHEN _direction = 'desc' AND _sort = 'account'       THEN s.name      ELSE NULL END) DESC,
        (CASE WHEN _direction = 'asc'  AND _sort = 'account'       THEN s.name      ELSE NULL END) ASC,
        -- Sort by effective vested amount proxied to _account_id
        (CASE WHEN _direction = 'desc' AND _sort = 'proxied_vests' THEN s.vests     ELSE NULL END) DESC,
        (CASE WHEN _direction = 'asc'  AND _sort = 'proxied_vests' THEN s.vests     ELSE NULL END) ASC,
        -- Tiebreaker: source_op for stable ordering
        (CASE WHEN _direction = 'desc'                             THEN s.source_op ELSE NULL END) DESC,
        (CASE WHEN _direction = 'asc'                              THEN s.source_op ELSE NULL END) ASC
      LIMIT  __max_page_size
      OFFSET __offset
    )
    SELECT
      ls.name::TEXT,
      ls.created_at,
      ls.vests::TEXT
    FROM limited_set ls;
END
$$;

RESET ROLE;
