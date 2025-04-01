SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_backend.get_account_proxied_vsf_votes(_account INT)
RETURNS TEXT[] -- noqa: LT01, CP05
LANGUAGE 'plpgsql'
STABLE
AS
$$
BEGIN
RETURN (
  WITH proxy_levels AS MATERIALIZED
  (
    SELECT 
      vpvv.proxied_vests as proxy, 
      vpvv.proxy_level 
    FROM hafbe_views.voters_proxied_vests_view vpvv 
    WHERE 
      vpvv.proxy_id= _account
    ORDER BY vpvv.proxy_level 
  ),
  populate_record AS MATERIALIZED
  (
    SELECT 0 as proxy, 1 as proxy_level
    UNION ALL
    SELECT 0 as proxy, 2 as proxy_level
    UNION ALL
    SELECT 0 as proxy, 3 as proxy_level
    UNION ALL
    SELECT 0 as proxy, 4 as proxy_level
  )
  SELECT 
    array_agg(coalesce(s.proxy::TEXT,"0") ORDER BY pr.proxy_level) 
  FROM populate_record pr
  LEFT JOIN proxy_levels s ON s.proxy_level = pr.proxy_level
);

END
$$;

RESET ROLE;