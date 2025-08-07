CREATE OR REPLACE FUNCTION hafbe_backend.get_account_proxies_power (
    _account_id INT,
    _page       INT DEFAULT 1
)
RETURNS SETOF hafbe_types.proxy_power
LANGUAGE sql
STABLE
AS $$
/* --------------------------------------------------------------------------
   1. Who is proxying to _account_id ?
--------------------------------------------------------------------------- */
WITH delegates AS (
  SELECT
    cap.account_id  AS delegator_id,
    da.name         AS delegator,
    bl.created_at   AS proxy_date
  FROM hafbe_app.current_account_proxies cap
  JOIN hafd.accounts        da ON da.id  = cap.account_id
  JOIN hive.blocks_view     bl ON bl.num = cap.source_op_block
  JOIN hive.operations_view ov
       ON  ov.id        = cap.source_op
      AND ov.block_num  = cap.source_op_block
      AND ov.body->>'type' = 'account_witness_proxy_operation'
  WHERE cap.proxy_id = _account_id
),

/* --------------------------------------------------------------------------
   2. Their own vesting shares
--------------------------------------------------------------------------- */
balance_agg AS (
  SELECT
    cab.account              AS delegator_id,
    MAX(cab.balance)         AS vesting_shares      -- their native VESTS
  FROM hafbe_bal.current_account_balances cab
  WHERE cab.nai = 37                         -- 37 = VESTS asset
    AND cab.account IN (SELECT delegator_id FROM delegates)
  GROUP BY cab.account
),

/* --------------------------------------------------------------------------
   3. Stake *already* proxied to each delegator (levels 1-4)
      → sum the four rows to match blockchain’s proxied_vsf_votes[0..3]
--------------------------------------------------------------------------- */
proxied_sum AS (
  SELECT
    vpvv.proxy_id            AS delegator_id,
    SUM(vpvv.proxied_vests)  AS proxied_vests_total
  FROM hafbe_backend.voters_proxied_vests_view vpvv
  WHERE vpvv.proxy_level BETWEEN 1 AND 4          -- depths 1-4 only
    AND vpvv.proxy_id IN (SELECT delegator_id FROM delegates)
  GROUP BY vpvv.proxy_id
)

/* --------------------------------------------------------------------------
   4. Final result
--------------------------------------------------------------------------- */
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
LIMIT  100
OFFSET (_page - 1) * 100;
$$;
