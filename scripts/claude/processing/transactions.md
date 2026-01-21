# Transaction Stats Processing

**Source**: `db/process_transaction_stats.sql`
**Function**: `hafbe_app.process_transaction_stats(_from INT, _to INT)`

## Purpose

Aggregates transaction counts by day and month periods. Tracks sum, count, min, max for each time period to power dashboard statistics.

## Tables

### `hafbe_app.transaction_stats_by_day`

| Column | Type | Description |
|--------|------|-------------|
| `trx_count` | INT | Total transactions on this day |
| `count_blocks` | INT | Number of blocks processed on this day |
| `min_trx` | INT | Minimum transactions in a single block |
| `max_trx` | INT | Maximum transactions in a single block |
| `last_block_num` | INT | Last block number included in stats |
| `updated_at` | TIMESTAMP | Date of statistics (PK) |

### `hafbe_app.transaction_stats_by_month`

| Column | Type | Description |
|--------|------|-------------|
| `trx_count` | INT | Total transactions in the month |
| `count_blocks` | INT | Number of blocks processed in month |
| `min_trx` | INT | Minimum transactions in a single block |
| `max_trx` | INT | Maximum transactions in a single block |
| `last_block_num` | INT | Last block number included in stats |
| `updated_at` | TIMESTAMP | First day of month (PK) |

## Key Patterns

### Transaction Counting

Counts transactions per block, then joins with block timestamps:

```sql
WITH gather_transactions AS MATERIALIZED (
  SELECT block_num, COUNT(*) AS trx_count
  FROM hafbe_app.transactions_view
  WHERE block_num BETWEEN _from AND _to
  GROUP BY block_num
),

join_blocks_date AS MATERIALIZED (
  SELECT
    bv.num AS block_num,
    COALESCE(gt.trx_count, 0) AS trx_count,
    date_trunc('day', bv.created_at) AS by_day,
    date_trunc('month', bv.created_at) AS by_month
  FROM hafbe_app.blocks_view bv
  LEFT JOIN gather_transactions gt ON gt.block_num = bv.num
  WHERE bv.num BETWEEN _from AND _to
)
```

**Note:** LEFT JOIN ensures blocks with 0 transactions are counted (COALESCE to 0).

### Time Period Aggregation

Groups by day and month:

```sql
SELECT
  SUM(trx_count)::INT AS sum_trx,
  COUNT(*)::INT AS count_blocks,
  MIN(trx_count)::INT AS min_trx,
  MAX(trx_count)::INT AS max_trx,
  MAX(block_num)::INT AS trx_block,
  by_day
FROM join_blocks_date
GROUP BY by_day
```

### Additive UPSERT Pattern

Statistics accumulate across processing batches:

```sql
INSERT INTO hafbe_app.transaction_stats_by_day AS trx_agg (...)
ON CONFLICT ON CONSTRAINT pk_transaction_stats_by_day DO UPDATE SET
  trx_count    = trx_agg.trx_count + EXCLUDED.trx_count,
  count_blocks = trx_agg.count_blocks + EXCLUDED.count_blocks,
  min_trx      = LEAST(EXCLUDED.min_trx, trx_agg.min_trx)::INT,
  max_trx      = GREATEST(EXCLUDED.max_trx, trx_agg.max_trx)::INT,
  last_block_num = EXCLUDED.last_block_num
```

**Additive fields:** `trx_count`, `count_blocks` (sum across batches)
**Min/Max tracking:** `LEAST()`, `GREATEST()` maintain true extremes
**Replacement:** `last_block_num` always takes the new value

## Data Flow

```
transactions_view
    │
    └── gather_transactions CTE (count per block)
            │
            └── join_blocks_date CTE (add timestamps)
                    │
                    ├── group_by_day CTE
                    │       │
                    │       └── UPSERT into transaction_stats_by_day
                    │
                    └── group_by_month CTE
                            │
                            └── UPSERT into transaction_stats_by_month
```

## Usage by API

This data powers dashboard and analytics endpoints:

| Endpoint | Usage |
|----------|-------|
| `get_transaction_stats()` | Daily/monthly transaction volume |
| Dashboard widgets | Transaction trends |

## How to Modify

### Adding a new aggregation field

1. Add column to both `transaction_stats_by_day` and `transaction_stats_by_month` in `hafbe_app.sql`
2. Add aggregation in `group_by_day` and `group_by_month` CTEs
3. Include in INSERT column list
4. Add appropriate UPSERT pattern (additive, min/max, or replacement)

### Adding a new time granularity

To add weekly aggregation:

1. Create `transaction_stats_by_week` table in `hafbe_app.sql`
2. Add `date_trunc('week', ...)` to `join_blocks_date` CTE
3. Add `group_by_week` CTE
4. Add INSERT with UPSERT logic
5. Create API endpoint to query the new table

### Performance considerations

- Uses MATERIALIZED CTEs to avoid re-scanning
- Transaction counting is efficient due to HAF indexing
- Blocks view lookup is indexed by block_num
- UPSERT pattern is efficient (single INSERT per time period)

## Testing

Transaction stats changes can be tested via:
- `tests/regression/` - Compare against hived snapshots
- `tests/tavern/patterns-mainnet/` - API tests for transaction endpoints
