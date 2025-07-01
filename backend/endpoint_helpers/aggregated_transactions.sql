-- noqa: disable=AL01, AM05

SET ROLE hafbe_owner;

DROP TYPE IF EXISTS hafbe_backend.transaction_stats CASCADE;
CREATE TYPE hafbe_backend.transaction_stats AS (
    date TIMESTAMP,
    trx_count INT,
    avg_trx INT,
    min_trx INT,
    max_trx INT,
    last_block_num INT
);

-- aggregate transactions into yearly stats using monthly stats
CREATE OR REPLACE FUNCTION hafbe_backend.transaction_stats_by_year(
    _from TIMESTAMP,
    _to TIMESTAMP
)
RETURNS SETOF hafbe_backend.transaction_stats -- noqa: LT01, CP05
LANGUAGE 'plpgsql'
STABLE
AS
$$
BEGIN
  RETURN QUERY
    WITH get_year AS (
        SELECT
            trx_count,
            avg_trx,
            min_trx,
            max_trx,
            last_block_num,
            updated_at,
            DATE_TRUNC('year', updated_at) AS by_year
        FROM hafbe_app.transaction_stats_by_month
        WHERE DATE_TRUNC('year', updated_at) BETWEEN _from AND _to
    )

    SELECT
        by_year,
        SUM(trx_count)::INT,
        AVG(avg_trx)::INT,
        MIN(min_trx)::INT,
        MAX(max_trx)::INT,
        MAX(last_block_num) AS last_block_num
    FROM get_year
    GROUP BY by_year;
END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.get_transaction_stats(
    _granularity hafbe_types.granularity,
    _from TIMESTAMP,
    _to TIMESTAMP
)
RETURNS SETOF hafbe_backend.transaction_stats -- noqa: LT01, CP05
LANGUAGE 'plpgsql'
STABLE
AS
$$
BEGIN
  IF _granularity = 'daily' THEN
    RETURN QUERY 
      SELECT 
        bh.updated_at,
        bh.trx_count,
        bh.avg_trx,
        bh.min_trx,
        bh.max_trx,
        bh.last_block_num
      FROM hafbe_app.transaction_stats_by_day bh
      WHERE bh.updated_at BETWEEN _from AND _to;

  ELSIF _granularity = 'monthly' THEN
    RETURN QUERY 
      SELECT 
        bh.updated_at,
        bh.trx_count,
        bh.avg_trx,
        bh.min_trx,
        bh.max_trx,
        bh.last_block_num
      FROM hafbe_app.transaction_stats_by_month bh
      WHERE bh.updated_at BETWEEN _from AND _to;

  ELSIF _granularity = 'yearly' THEN
    RETURN QUERY 
      SELECT 
        bh.date,
        bh.trx_count,
        bh.avg_trx,
        bh.min_trx,
        bh.max_trx,
        bh.last_block_num
      FROM hafbe_backend.transaction_stats_by_year(_from, _to) bh;

  ELSE
    RAISE EXCEPTION 'Unsupported granularity: %', _granularity;
  END IF;
END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.get_transaction_aggregation(
    _granularity hafbe_types.granularity,
    _direction hafbe_types.sort_direction,
    _from_block INT,
    _to_block INT
)
RETURNS SETOF hafbe_backend.transaction_stats -- noqa: LT01, CP05
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
    __from INT;
    __to INT;
    __from_timestamp TIMESTAMP;
    __to_timestamp TIMESTAMP;
    __granularity TEXT;
    __one_period INTERVAL;
    -- Get the current block number from the context
    __hafbe_current_block INT := (SELECT current_block_num FROM hafd.contexts WHERE name = 'hafbe_app');
BEGIN
  SELECT from_block, to_block
  INTO __from, __to
  FROM hafbe_backend.blocksearch_range(_from_block, _to_block, __hafbe_current_block);

  __granularity := (
    CASE 
      WHEN _granularity = 'daily' THEN 'day'
      WHEN _granularity = 'monthly' THEN 'month'
      WHEN _granularity = 'yearly' THEN 'year'
      ELSE NULL
    END
  );

  __from_timestamp := DATE_TRUNC(__granularity,(SELECT b.created_at FROM hive.blocks_view b WHERE b.num = __from)::TIMESTAMP);
  __to_timestamp := DATE_TRUNC(__granularity, (SELECT b.created_at FROM hive.blocks_view b WHERE b.num = __to)::TIMESTAMP);


  __one_period := ('1 ' || __granularity )::INTERVAL;

  RETURN QUERY (
    WITH date_series AS (
      SELECT generate_series(__from_timestamp, __to_timestamp, __one_period) AS date
    ),
    get_daily_aggregation AS MATERIALIZED (
      SELECT 
        bh.date,
        bh.trx_count,
        bh.avg_trx,
        bh.min_trx,
        bh.max_trx,
        bh.last_block_num
      FROM hafbe_backend.get_transaction_stats(_granularity, __from_timestamp, __to_timestamp) bh
    ),
    transaction_records AS (
      SELECT 
        ds.date,
        COALESCE(bh.trx_count,0) AS trx_count,
        COALESCE(bh.avg_trx,0) AS avg_trx,
        COALESCE(bh.min_trx,0) AS min_trx,
        COALESCE(bh.max_trx,0) AS max_trx,
        COALESCE(bh.last_block_num,NULL) AS last_block_num
      FROM date_series ds
      LEFT JOIN get_daily_aggregation bh ON ds.date = bh.date
    ),
    join_missing_block AS (
      SELECT
        fb.date,
        fb.trx_count,
        fb.avg_trx,
        fb.min_trx,
        fb.max_trx,
        COALESCE(fb.last_block_num, jl.last_block_num) AS last_block_num
      FROM transaction_records fb
      LEFT JOIN LATERAL (
        SELECT
          b.num AS last_block_num
        FROM hive.blocks_view b
        WHERE b.created_at <= fb.date + __one_period
        ORDER BY b.created_at DESC
        LIMIT 1
      ) jl ON fb.last_block_num IS NULL
    )
    SELECT 
      LEAST(fb.date + __one_period, CURRENT_TIMESTAMP)::TIMESTAMP AS adjusted_date,
      fb.trx_count::INT,
      fb.avg_trx::INT,
      fb.min_trx::INT,
      fb.max_trx::INT,
      fb.last_block_num::INT
    FROM join_missing_block fb
    ORDER BY
      (CASE WHEN _direction = 'desc' THEN fb.date ELSE NULL END) DESC,
      (CASE WHEN _direction = 'asc' THEN fb.date ELSE NULL END) ASC
  );

END
$$;

RESET ROLE;
