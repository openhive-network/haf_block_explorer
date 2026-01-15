CREATE OR REPLACE FUNCTION hafbe_backend.get_account_proxies_power (
    _account_id INT,
    _page       INT DEFAULT 1
)
RETURNS SETOF hafbe_backend.proxy_power
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  __nai_vests     INT := btracker_backend.nai_vests();
  __max_page_size INT := hafbe_backend.default_max_page_size();
BEGIN
  RETURN QUERY
    WITH delegates AS MATERIALIZED (
      SELECT
        cap.account_id,
        cap.source_op,
        -- block number extracted from operation id - the block_num column will be removed
        cap.source_op_block
      FROM hafbe_backend.current_account_proxies_view cap
      WHERE cap.proxy_id = _account_id
      ORDER BY cap.source_op DESC
      -- always calculate pages first before any joins if it is possible
      LIMIT  __max_page_size
      OFFSET (_page - 1) * __max_page_size
    )
    SELECT
      av.name::TEXT,
      bv.created_at,
      -- vests must be converted to TEXT
      -- because these values are big enough to be compressed by json and ultimately the returned value is incorrect
      (
        -- vests of the account - by his delayed vests + proxied vests
        -- (proxy vests are calculated with delayed vests taken into account)
        COALESCE(cab.balance, 0) - COALESCE(aw.delayed_vests,0) + COALESCE(avs.proxied_vests, 0)
      )::TEXT
    FROM delegates d
    -- always use views if avalable (hafd.operation_types is an exception)
    JOIN hive.accounts_view av        ON av.id = d.account_id
    JOIN hive.blocks_view bv          ON bv.num = d.source_op_block
    -- no need for grouping
    LEFT JOIN current_account_balances cab ON cab.account = d.account_id AND cab.nai = __nai_vests
    -- (without delayed vests the proxied power is not accurate)
    LEFT JOIN account_withdraws aw    ON aw.account = d.account_id
    -- use voters_proxied_vests_sum_view where the grouping is already done - simpler code
    LEFT JOIN hafbe_backend.voters_proxied_vests_sum_view avs ON avs.proxy_id = d.account_id
    -- order again at the end of the query to ensure that the pagination is correct
    ORDER BY d.source_op DESC;
END
$$;
