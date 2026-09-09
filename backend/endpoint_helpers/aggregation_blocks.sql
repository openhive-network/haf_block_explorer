SET ROLE hafbe_owner;

/*
 * Select end-of-period blocks from existing transaction statistics. Bounds select
 * whole containing periods, as in transaction-statistics. Empty periods use the
 * last available earlier block; no raw block-history aggregation is needed.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.get_aggregation_blocks(
    _granularity   hafbe_backend.hbd_granularity,
    _direction     hafbe_backend.sort_direction,
    _from_block    INT,
    _to_block      INT,
    _current_block INT
)
RETURNS TABLE(date TIMESTAMP, last_block_num INT)
LANGUAGE plpgsql STABLE
SET jit = OFF
AS
$$
DECLARE
  __from        INT;
  __to          INT;
  __from_ts     TIMESTAMP;
  __to_ts       TIMESTAMP;
  __granularity TEXT := CASE _granularity
    WHEN 'daily'   THEN 'day'
    WHEN 'weekly'  THEN 'week'
    WHEN 'monthly' THEN 'month'
    WHEN 'yearly'  THEN 'year'
  END;
  __one_period INTERVAL := ('1 ' || __granularity)::INTERVAL;
BEGIN
  SELECT from_block, to_block INTO __from, __to
  FROM hafbe_backend.blocksearch_range(_from_block, _to_block, _current_block);

  __from_ts := DATE_TRUNC(__granularity, (
    SELECT b.created_at FROM hafbe_app.blocks_view b
    WHERE b.num = __from AND b.num <= _current_block
  )::TIMESTAMP);
  __to_ts := DATE_TRUNC(__granularity, (
    SELECT b.created_at FROM hafbe_app.blocks_view b
    WHERE b.num = __to AND b.num <= _current_block
  )::TIMESTAMP);

  RETURN QUERY
    WITH period_stats AS (
      SELECT s.updated_at AS period_start, s.last_block_num
      FROM hafbe_app.transaction_stats_by_day s
      WHERE _granularity = 'daily'
        AND s.updated_at BETWEEN __from_ts AND __to_ts

      UNION ALL

      SELECT DATE_TRUNC('week', s.updated_at), MAX(s.last_block_num)
      FROM hafbe_app.transaction_stats_by_day s
      WHERE _granularity = 'weekly'
        AND s.updated_at >= __from_ts
        AND s.updated_at < __to_ts + __one_period
      GROUP BY DATE_TRUNC('week', s.updated_at)

      UNION ALL

      SELECT s.updated_at, s.last_block_num
      FROM hafbe_app.transaction_stats_by_month s
      WHERE _granularity = 'monthly'
        AND s.updated_at BETWEEN __from_ts AND __to_ts

      UNION ALL

      SELECT DATE_TRUNC('year', s.updated_at), MAX(s.last_block_num)
      FROM hafbe_app.transaction_stats_by_month s
      WHERE _granularity = 'yearly'
        AND s.updated_at >= __from_ts
        AND s.updated_at < __to_ts + __one_period
      GROUP BY DATE_TRUNC('year', s.updated_at)
    ),
    period_blocks AS (
      SELECT
        ds.period_start,
        CASE WHEN s.last_block_num <= _current_block THEN s.last_block_num END AS last_block_num
      FROM generate_series(__from_ts, __to_ts, __one_period) ds(period_start)
      LEFT JOIN period_stats s ON s.period_start = ds.period_start
    )
    SELECT
      LEAST(pb.period_start + __one_period, CURRENT_TIMESTAMP AT TIME ZONE 'UTC')::TIMESTAMP,
      COALESCE(pb.last_block_num, missing.last_block_num)
    FROM period_blocks pb
    LEFT JOIN LATERAL (
      SELECT b.num AS last_block_num
      FROM hafbe_app.blocks_view b
      WHERE pb.last_block_num IS NULL
        AND b.created_at < pb.period_start + __one_period
        AND b.num <= _current_block
      ORDER BY b.created_at DESC
      LIMIT 1
    ) missing ON TRUE
    WHERE COALESCE(pb.last_block_num, missing.last_block_num) IS NOT NULL
    ORDER BY
      (CASE WHEN _direction = 'desc' THEN pb.period_start END) DESC,
      (CASE WHEN _direction = 'asc'  THEN pb.period_start END) ASC;
END
$$;

RESET ROLE;
