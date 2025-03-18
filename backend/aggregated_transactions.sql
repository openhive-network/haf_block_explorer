-- noqa: disable=AL01, AM05

SET ROLE hafbe_owner;

DROP TYPE IF EXISTS hafbe_backend.transaction_stats CASCADE;
CREATE TYPE hafbe_backend.transaction_stats AS (
    date TIMESTAMP,
    trx_count INT,
    avg_trx INT ,
    min_trx INT,
    max_trx INT,
    last_block_num INT
);

CREATE OR REPLACE VIEW hafbe_backend.transaction_stats_by_year AS
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
)

SELECT
    by_year AS updated_at,
    SUM(trx_count) AS trx_count,
    AVG(avg_trx) AS avg_trx,
    MIN(min_trx) AS min_trx,
    MAX(max_trx) AS max_trx,
    MAX(last_block_num) AS last_block_num
FROM get_year
GROUP BY by_year;

CREATE OR REPLACE FUNCTION hafbe_backend.get_transaction_stats(
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
    __hafbe_current_block INT := (SELECT current_block_num FROM hafd.contexts WHERE name = 'hafbe_app');
BEGIN
  SELECT from_block, to_block
  INTO __from, __to
  FROM hafbe_backend.blocksearch_range(_from_block, _to_block, __hafbe_current_block);

  IF _granularity = 'daily' THEN
    RETURN QUERY (
      SELECT 
        fb.date,
        fb.trx_count,
        fb.avg_trx,
        fb.min_trx,
        fb.max_trx,
        fb.last_block_num
      FROM hafbe_backend.get_transaction_stats_by_day(
        _direction,
        __from,
        __to
      ) fb
    );
  ELSEIF _granularity = 'monthly' THEN
    RETURN QUERY (
      SELECT 
        fb.date,
        fb.trx_count,
        fb.avg_trx,
        fb.min_trx,
        fb.max_trx,
        fb.last_block_num
      FROM hafbe_backend.get_transaction_stats_by_month(
        _direction,
        __from,
        __to
      ) fb
    );
  ELSEIF _granularity = 'yearly' THEN
    RETURN QUERY (
      SELECT 
        fb.date,
        fb.trx_count,
        fb.avg_trx,
        fb.min_trx,
        fb.max_trx,
        fb.last_block_num
      FROM hafbe_backend.get_transaction_stats_by_year(
        _direction,
        __from,
        __to
      ) fb
    );
  ELSE
    RAISE EXCEPTION 'Unknown granularity: %', _granularity;
  END IF;
END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.get_transaction_stats_by_day(
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
  _from_timestamp TIMESTAMP := DATE_TRUNC('day',(SELECT b.created_at FROM hive.blocks_view b WHERE b.num = _from_block)::TIMESTAMP);
  _to_timestamp TIMESTAMP := DATE_TRUNC('day', (SELECT b.created_at FROM hive.blocks_view b WHERE b.num = _to_block)::TIMESTAMP);
BEGIN

RETURN QUERY (
  WITH date_series AS (
    SELECT generate_series(_from_timestamp, _to_timestamp, '1 day') AS date
  ),
  get_daily_aggregation AS MATERIALIZED (
    SELECT 
      bh.updated_at,
      bh.trx_count,
      bh.avg_trx,
      bh.min_trx,
      bh.max_trx,
      bh.last_block_num
    FROM hafbe_app.transaction_stats_by_day bh
    WHERE bh.updated_at BETWEEN _from_timestamp AND _to_timestamp
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
    LEFT JOIN get_daily_aggregation bh ON ds.date = bh.updated_at
  )
  SELECT 
    LEAST(fb.date + INTERVAL '1 day' - INTERVAL '1 second', CURRENT_TIMESTAMP)::TIMESTAMP AS adjusted_date,
    fb.trx_count::INT,
    fb.avg_trx::INT,
    fb.min_trx::INT,
    fb.max_trx::INT,
    fb.last_block_num::INT
  FROM transaction_records fb
  ORDER BY
    (CASE WHEN _direction = 'desc' THEN fb.date ELSE NULL END) DESC,
    (CASE WHEN _direction = 'asc' THEN fb.date ELSE NULL END) ASC
);
END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.get_transaction_stats_by_month(
    _account_id INT,
    _coin_type INT,
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
  _from_timestamp TIMESTAMP := DATE_TRUNC('month',(SELECT b.created_at FROM hive.blocks_view b WHERE b.num = _from_block)::TIMESTAMP);
  _to_timestamp TIMESTAMP := DATE_TRUNC('month', (SELECT b.created_at FROM hive.blocks_view b WHERE b.num = _to_block)::TIMESTAMP);
BEGIN
RETURN QUERY (
  WITH date_series AS (
    SELECT generate_series(_from_timestamp, _to_timestamp, '1 month') AS date
  ),
  get_monthly_aggregation AS MATERIALIZED (
    SELECT 
      bh.updated_at,
      bh.trx_count,
      bh.avg_trx,
      bh.min_trx,
      bh.max_trx,
      bh.last_block_num
    FROM hafbe_app.transaction_stats_by_month bh
    WHERE bh.updated_at BETWEEN _from_timestamp AND _to_timestamp
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
    LEFT JOIN get_monthly_aggregation bh ON ds.date = bh.updated_at
  )
  SELECT 
    LEAST(fb.date + INTERVAL '1 month' - INTERVAL '1 second', CURRENT_TIMESTAMP)::TIMESTAMP AS adjusted_date,
    fb.trx_count::INT,
    fb.avg_trx::INT,
    fb.min_trx::INT,
    fb.max_trx::INT,
    fb.last_block_num::INT
  FROM transaction_records fb
  ORDER BY
    (CASE WHEN _direction = 'desc' THEN fb.date ELSE NULL END) DESC,
    (CASE WHEN _direction = 'asc' THEN fb.date ELSE NULL END) ASC
);
END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.get_transaction_stats_by_year(
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
  _from_timestamp TIMESTAMP := DATE_TRUNC('year',(SELECT b.created_at FROM hive.blocks_view b WHERE b.num = _from_block)::TIMESTAMP);
  _to_timestamp TIMESTAMP := DATE_TRUNC('year', (SELECT b.created_at FROM hive.blocks_view b WHERE b.num = _to_block)::TIMESTAMP);
BEGIN
RETURN QUERY (
  WITH date_series AS (
    SELECT generate_series(_from_timestamp, _to_timestamp, '1 year') AS date
  ),
  get_yearly_aggregation AS MATERIALIZED (
    SELECT 
      bh.updated_at,
      bh.trx_count,
      bh.avg_trx,
      bh.min_trx,
      bh.max_trx,
      bh.last_block_num
    FROM hafbe_backend.transaction_stats_by_year bh
    WHERE bh.updated_at BETWEEN _from_timestamp AND _to_timestamp
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
    LEFT JOIN get_yearly_aggregation bh ON ds.date = bh.updated_at
  )
  SELECT 
    LEAST(fb.date + INTERVAL '1 year' - INTERVAL '1 second', CURRENT_TIMESTAMP)::TIMESTAMP AS adjusted_date,
    fb.trx_count::INT,
    fb.avg_trx::INT,
    fb.min_trx::INT,
    fb.max_trx::INT,
    fb.last_block_num::INT
  FROM transaction_records fb
  ORDER BY
    (CASE WHEN _direction = 'desc' THEN fb.date ELSE NULL END) DESC,
    (CASE WHEN _direction = 'asc' THEN fb.date ELSE NULL END) ASC
);
END
$$;

RESET ROLE;
