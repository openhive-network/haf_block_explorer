SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_app.process_transaction_stats(_from INT, _to INT)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
SET enable_bitmapscan = OFF
AS
$$
DECLARE
  __trx_by_day INT;
  __trx_by_month INT;
BEGIN
  WITH gather_transactions AS MATERIALIZED (
    SELECT 
      block_num, 
      COUNT(*) as trx_count
    FROM hafbe_app.transactions_view
    WHERE 
      block_num BETWEEN _from AND _to
    GROUP BY block_num
  ),
  join_blocks_date AS MATERIALIZED (
    SELECT 
      bv.num as block_num, 
      COALESCE(gt.trx_count, 0) AS trx_count, 
      date_trunc('day',bv.created_at) as by_day, 
      date_trunc('month',bv.created_at) as by_month
    FROM hafbe_app.blocks_view bv
    LEFT JOIN gather_transactions gt ON gt.block_num = bv.num
    WHERE bv.num BETWEEN _from AND _to
  ),
  group_by_day AS (
    SELECT 
      sum(trx_count)::INT AS sum_trx,
      avg(trx_count)::INT AS avg_trx,
      min(trx_count)::INT AS min_trx,
      max(trx_count)::INT AS max_trx,
      max(block_num)::INT AS trx_block,
      by_day
    FROM join_blocks_date
    GROUP BY by_day
    ORDER BY by_day
  ),
  group_by_month AS (
    SELECT 
      sum(trx_count)::INT AS sum_trx,
      avg(trx_count)::INT AS avg_trx,
      min(trx_count)::INT AS min_trx,
      max(trx_count)::INT AS max_trx,
      max(block_num)::INT AS trx_block,
      by_month
    FROM join_blocks_date
    GROUP BY by_month
    ORDER BY by_month
  ),
  insert_trx_stats_by_day AS (
    INSERT INTO hafbe_app.transaction_stats_by_day AS trx_agg
      (trx_count, avg_trx, min_trx, max_trx, last_block_num, updated_at)
    SELECT 
      sum_trx,
      avg_trx,
      min_trx,
      max_trx,
      trx_block,
      by_day
    FROM group_by_day 
    ON CONFLICT ON CONSTRAINT pk_transaction_stats_by_day DO 
    UPDATE SET 
      trx_count = trx_agg.trx_count + EXCLUDED.trx_count,
      avg_trx = ((EXCLUDED.avg_trx + trx_agg.avg_trx) / 2)::INT,
      min_trx = LEAST(EXCLUDED.min_trx, trx_agg.min_trx)::INT,
      max_trx = GREATEST(EXCLUDED.max_trx, trx_agg.max_trx)::INT,
      last_block_num = EXCLUDED.last_block_num
    RETURNING (xmax = 0) as is_new_entry, trx_agg.updated_at
  ),
  insert_trx_stats_by_month AS (
    INSERT INTO hafbe_app.transaction_stats_by_month AS trx_agg
      (trx_count, avg_trx, min_trx, max_trx, last_block_num, updated_at)
    SELECT 
      sum_trx,
      avg_trx,
      min_trx,
      max_trx,
      trx_block,
      by_month
    FROM group_by_month 
    ON CONFLICT ON CONSTRAINT pk_transaction_stats_by_month DO 
    UPDATE SET 
      trx_count = trx_agg.trx_count + EXCLUDED.trx_count,
      avg_trx = ((EXCLUDED.avg_trx + trx_agg.avg_trx) / 2)::INT,
      min_trx = LEAST(EXCLUDED.min_trx, trx_agg.min_trx)::INT,
      max_trx = GREATEST(EXCLUDED.max_trx, trx_agg.max_trx)::INT,
      last_block_num = EXCLUDED.last_block_num
    RETURNING (xmax = 0) as is_new_entry, trx_agg.updated_at
  )
  SELECT
    (SELECT count(*) FROM insert_trx_stats_by_day) as by_day,
    (SELECT count(*) FROM insert_trx_stats_by_month) AS by_month
  INTO __trx_by_day, __trx_by_month;

END
$$;

RESET ROLE;
