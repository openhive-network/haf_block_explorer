CREATE OR REPLACE FUNCTION hafbe_backend.get_account_proxies_power (
    _account_id INT,
    _page       INT DEFAULT 1
)
RETURNS SETOF hafbe_types.proxy_power
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  __max_page_size INT := 100; -- max page size for pagination
BEGIN

  /*
  WITH delegates AS (

    -- (comment) don't join on the beginning of the query
    -- (comment) try to calculate pages first and join in the final query

    SELECT
      cap.account_id  AS delegator_id,
      da.name         AS delegator,
      bl.created_at   AS proxy_date
    FROM hafbe_app.current_account_proxies cap

    -- (comment) use views instead of tables

    JOIN hafd.accounts        da ON da.id  = cap.account_id
    JOIN hive.blocks_view     bl ON bl.num = cap.source_op_block

    -- (comment) what is that join for?
    -- (comment) only thing that comes to mind is that it is for ensuring that the operation that edited the proxy exists?
    -- (comment) usless join generally

    JOIN hive.operations_view ov
        ON  ov.id        = cap.source_op
        AND ov.block_num  = cap.source_op_block
        AND ov.body->>'type' = 'account_witness_proxy_operation'
    WHERE cap.proxy_id = _account_id
  ),
  balance_agg AS (
    SELECT
      cab.account              AS delegator_id,

      -- (comment) what is that MAX for?
      -- (comment) there is primary key on  (account, nai) - there is no aggregation needed

      MAX(cab.balance)         AS vesting_shares      -- their native VESTS
    FROM hafbe_bal.current_account_balances cab
    WHERE cab.nai = 37                         -- 37 = VESTS asset
      AND cab.account IN (SELECT delegator_id FROM delegates)

    -- (comment) what is that group for?
    -- (comment) there is primary key on  (account, nai) - there is no aggregation needed

    GROUP BY cab.account
  ),
  proxied_sum AS (

    -- (comment) use voters_proxied_vests_sum_view instead of this
    -- (comment) it is already aggregated there

    SELECT
      vpvv.proxy_id            AS delegator_id,
      SUM(vpvv.proxied_vests)  AS proxied_vests_total
    FROM hafbe_backend.voters_proxied_vests_view vpvv
    WHERE vpvv.proxy_level BETWEEN 1 AND 4          -- depths 1-4 only
      AND vpvv.proxy_id IN (SELECT delegator_id FROM delegates)
    GROUP BY vpvv.proxy_id
  )
  SELECT
    d.delegator,
    d.proxy_date,
    COALESCE(b.vesting_shares, 0)          -- their own stake
    + COALESCE(p.proxied_vests_total, 0)   -- plus everything already proxied to them
      AS proxy_power
  FROM delegates       d
  LEFT JOIN balance_agg b ON b.delegator_id = d.delegator_id
  LEFT JOIN proxied_sum p ON p.delegator_id = d.delegator_id
  ORDER BY d.proxy_date DESC

  -- (comment) final query performance is slow due to:
  -- excessive joins made on the beginning of the query
  -- excessive aggregations that are not needed
  -- and the final query is paginated AFTER those joins and aggregations which slows down the query even more

  LIMIT  100
  OFFSET (_page - 1) * 100;
  */

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
    LEFT JOIN current_account_balances cab ON cab.account = d.account_id AND cab.nai = 37
    -- (without delayed vests the proxied power is not accurate)
    LEFT JOIN account_withdraws aw    ON aw.account = d.account_id
    -- use voters_proxied_vests_sum_view where the grouping is already done - simpler code
    LEFT JOIN hafbe_backend.voters_proxied_vests_sum_view avs ON avs.proxy_id = d.account_id
    -- order again at the end of the query to ensure that the pagination is correct
    ORDER BY d.source_op DESC;

    -- old version: Execution Time: 2269.497 ms -- blocktrades
    -- old version: Execution Time: 7203.320 ms -- gtg
    -- old version: Execution Time: 711.519 ms  -- arcange (only 1 proxy account)

    -- new version: Execution Time: 75.345 ms -- blocktrades
    -- new version: Execution Time: 40.623 ms -- gtg
    -- new version: Execution Time: 30.473 ms -- arcange (only 1 proxy account)
END
$$;
