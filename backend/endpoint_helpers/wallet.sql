SET ROLE hafbe_owner;

/*
 * get_wallet_aggregation: Returns new-wallet counts + cumulative total per period.
 *
 * Source: hafbe_app.account_parameters.created — already populated by
 * process_account_stats(), one row per Hive account, no extra sync work needed.
 * An index on account_parameters(created) makes the range scan fast.
 *
 * Steps:
 *   1. Convert block range → timestamp range (period-boundary truncated).
 *   2. Generate a complete date series so empty periods appear with 0.
 *   3. Count new wallets per period from account_parameters.
 *   4. Compute baseline = wallets created before the requested range start,
 *      so total_wallets is the absolute chain count, not just within-range.
 *   5. Running SUM over date series gives total_wallets per row.
 *   6. Cap the latest period date at CURRENT_TIMESTAMP (partial day/month).
 */
CREATE OR REPLACE FUNCTION hafbe_backend.get_wallet_aggregation(
    _granularity hafbe_backend.granularity,
    _direction   hafbe_backend.sort_direction,
    _from_block  INT,
    _to_block    INT
)
RETURNS SETOF hafbe_backend.wallet_stats
LANGUAGE 'plpgsql'
STABLE
SET jit = OFF
AS
$$
DECLARE
  __from                INT;
  __to                  INT;
  __from_timestamp      TIMESTAMP;
  __to_timestamp        TIMESTAMP;
  __granularity         TEXT;
  __one_period          INTERVAL;
  __baseline            INT;
  __hafbe_current_block INT := (SELECT current_block_num FROM hafd.contexts WHERE name = 'hafbe_app');
BEGIN
  SELECT from_block, to_block
  INTO __from, __to
  FROM hafbe_backend.blocksearch_range(_from_block, _to_block, __hafbe_current_block);

  __granularity := CASE
    WHEN _granularity = 'daily'   THEN 'day'
    WHEN _granularity = 'monthly' THEN 'month'
    WHEN _granularity = 'yearly'  THEN 'year'
  END;

  __from_timestamp := DATE_TRUNC(
    __granularity,
    (SELECT b.created_at FROM hive.blocks_view b WHERE b.num = __from)::TIMESTAMP
  );
  __to_timestamp := DATE_TRUNC(
    __granularity,
    (SELECT b.created_at FROM hive.blocks_view b WHERE b.num = __to)::TIMESTAMP
  );

  __one_period := ('1 ' || __granularity)::INTERVAL;

  -- Wallets created strictly before the requested window (absolute chain baseline).
  SELECT COALESCE(COUNT(*), 0)::INT
  INTO __baseline
  FROM hafbe_app.account_parameters
  WHERE created < __from_timestamp;

  RETURN QUERY (
    WITH date_series AS (
      SELECT generate_series(__from_timestamp, __to_timestamp, __one_period) AS period
    ),

    counts AS MATERIALIZED (
      SELECT
        DATE_TRUNC(__granularity, ap.created) AS period,
        COUNT(*)::INT AS new_wallets
      FROM hafbe_app.account_parameters ap
      WHERE ap.created BETWEEN __from_timestamp
                           AND __to_timestamp + __one_period - INTERVAL '1 second'
      GROUP BY DATE_TRUNC(__granularity, ap.created)
    ),

    filled AS (
      SELECT
        ds.period,
        COALESCE(c.new_wallets, 0) AS new_wallets
      FROM date_series ds
      LEFT JOIN counts c ON c.period = ds.period
    ),

    cumulative AS (
      SELECT
        f.period,
        f.new_wallets,
        __baseline + SUM(f.new_wallets) OVER (ORDER BY f.period) AS total_wallets
      FROM filled f
    )

    SELECT
      LEAST(c.period + __one_period, CURRENT_TIMESTAMP)::TIMESTAMP AS date,
      c.new_wallets::INT,
      c.total_wallets::INT
    FROM cumulative c
    ORDER BY
      (CASE WHEN _direction = 'desc' THEN c.period ELSE NULL END) DESC,
      (CASE WHEN _direction = 'asc'  THEN c.period ELSE NULL END) ASC
  );
END
$$;

RESET ROLE;
