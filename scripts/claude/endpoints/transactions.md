# Transaction Endpoints

Transaction endpoints provide aggregated statistics about blockchain transactions.

## Endpoints

### GET /transaction-statistics

**Function:** `hafbe_endpoints.get_transaction_statistics`
**File:** `endpoints/transactions/get_transaction_statistics.sql`

Get aggregated transaction statistics over time (daily, monthly, or yearly).

#### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `granularity` | granularity | No | yearly | Aggregation level: `daily`, `monthly`, `yearly` |
| `direction` | sort_direction | No | desc | Sort order (by date) |
| `page` | INT | No | 1 | Page number (1-indexed) of periods, in the sorted order |
| `page-size` | INT | No | 100 | Periods returned per page (max 1000) |
| `from-block` | TEXT | No | NULL | Lower bound (block num or timestamp) |
| `to-block` | TEXT | No | NULL | Upper bound (block num or timestamp) |

#### Response

Returns `hafbe_backend.transaction_stats_return` — a **paginated wrapper**, not a
bare array. `stats` holds the requested page of `hafbe_backend.transaction_stats`
records:
```json
{
  "total_periods": 11,
  "total_pages": 1,
  "stats": [
    {
      "date": "2017-01-01T00:00:00",
      "trx_count": 6961192,
      "avg_trx": 1,
      "min_trx": 0,
      "max_trx": 89,
      "last_block_num": 5000000
    }
  ]
}
```

**Wrapper fields:**
- `total_periods` - Total number of periods in the range (across all pages); a pure function of `(granularity, range)`
- `total_pages` - `ceil(total_periods / page-size)`
- `stats` - The requested page of records

**`stats[]` fields:**
- `date` - Period end date (capped at current time for the in-progress period)
- `trx_count` - Total transactions in period
- `avg_trx` - Average transactions per block
- `min_trx` - Minimum transactions in a block
- `max_trx` - Maximum transactions in a block
- `last_block_num` - Last block in the period

#### Examples

```bash
# Get yearly transaction stats (first page, 100 periods)
curl "http://localhost:3000/hafbe-api/transaction-statistics"

# Get monthly stats
curl "http://localhost:3000/hafbe-api/transaction-statistics?granularity=monthly"

# Get daily stats for a specific range
curl "http://localhost:3000/hafbe-api/transaction-statistics?granularity=daily&from-block=2020-01-01%2000:00:00&to-block=2020-12-31%2023:59:59"

# Second page of daily stats, 50 periods per page
curl "http://localhost:3000/hafbe-api/transaction-statistics?granularity=daily&page=2&page-size=50"

# Sort oldest first
curl "http://localhost:3000/hafbe-api/transaction-statistics?direction=asc"
```

### GET /operation-type-statistics

**Function:** `hafbe_endpoints.get_operation_type_statistics`
**File:** `endpoints/transactions/get_operation_type_statistics.sql`

Get per-op-type operation counts plus transaction totals for each period. Same
granularity/direction/pagination/range model as `/transaction-statistics`.

#### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `granularity` | granularity | No | yearly | Aggregation level: `daily`, `monthly`, `yearly` |
| `direction` | sort_direction | No | desc | Sort order (by date) |
| `page` | INT | No | 1 | Page number (1-indexed) of periods, in the sorted order |
| `page-size` | INT | No | 100 | Periods returned per page (max 1000) |
| `from-block` | TEXT | No | NULL | Lower bound (block num or timestamp) |
| `to-block` | TEXT | No | NULL | Upper bound (block num or timestamp) |
| `op-types` | TEXT | No | NULL | Comma-separated `op_type_id` filter (e.g. `0,1,18`); NULL = all |

#### Response

Returns `hafbe_backend.operation_type_stats_return` — the same paginated wrapper
shape; `stats[]` holds `hafbe_backend.operation_type_stats` records:
```json
{
  "total_periods": 3752,
  "total_pages": 38,
  "stats": [
    {
      "date": "2017-01-02T00:00:00",
      "total_transactions": 412000,
      "total_operations": 365000,
      "operations": [
        {"op_type_id": 0,  "op_count": 98000},
        {"op_type_id": 18, "op_count": 210000}
      ],
      "last_block_num": 5000000
    }
  ]
}
```

**`stats[]` fields:**
- `date` - Period end date (capped at current time for the in-progress period)
- `total_transactions` - Total transactions in the period (always unfiltered by `op-types`)
- `total_operations` - Total operations in the period (sum of `operations[].op_count`; reflects the `op-types` filter when set)
- `operations` - Per-op-type breakdown (`op_type_id`, `op_count`)
- `last_block_num` - Last block in the period

Note: `total_periods` is independent of the `op-types` filter (every period is
one row, even when its filtered breakdown is empty).

#### Examples

```bash
# Yearly per-op-type stats (first page)
curl "http://localhost:3000/hafbe-api/operation-type-statistics"

# Daily, second page of 50 periods, only vote (0) and custom_json (18)
curl "http://localhost:3000/hafbe-api/operation-type-statistics?granularity=daily&page=2&page-size=50&op-types=0,18"
```

## Return Types

Defined in `endpoints/types/transactions.sql`:

| Type | Description |
|------|-------------|
| `hafbe_backend.transaction_stats` | Transaction aggregation record (one period) |
| `hafbe_backend.transaction_stats_return` | Paginated wrapper: `total_periods`, `total_pages`, `stats[]` |
| `hafbe_backend.operation_type_stats` | Per-op-type aggregation record (one period), incl. nested `operations[]` |
| `hafbe_backend.operation_type_stats_return` | Paginated wrapper for operation-type stats |
| `hafbe_backend.period_op_type_count` | `{op_type_id, op_count}` element of `operations[]` |
| `hafbe_backend.granularity` | Enum: `daily`, `monthly`, `yearly` |

## Implementation Details

### Data Source

Transaction statistics are pre-aggregated in processing and stored in:
- `hafbe_app.transaction_stats_by_day` - Daily aggregations
- `hafbe_app.transaction_stats_by_month` - Monthly aggregations

Per-op-type statistics (for `/operation-type-statistics`) are stored in:
- `hafbe_app.operation_type_stats_by_day` - Daily per-op-type counts
- `hafbe_app.operation_type_stats_by_month` - Monthly per-op-type counts

Yearly granularity is aggregated on the fly from the monthly tables in both cases.

### Granularity Handling

The `granularity` parameter controls the aggregation level:
- `daily` - Returns data from `transaction_stats_by_day`
- `monthly` - Returns data from `transaction_stats_by_month`
- `yearly` - Aggregates monthly data into years

### Caching

- Historical data (to_block <= irreversible): `max-age=31536000`
- Live data: `max-age=2`

## Helper Functions

Located in `backend/endpoint_helpers/`:

| Function | File | Purpose |
|----------|------|---------|
| `get_transaction_aggregation()` | transactions.sql | Page over transaction stats for the range |
| `get_operation_type_aggregation()` | operation_type_stats.sql | Page over per-op-type stats for the range |
| `aggregation_period_count()` | ../utilities/blocksearch.sql | `total_periods` for the wrapper (drives `total_pages`); resolves the range via `blocksearch_range` + counts periods |
| `blocksearch_range()` | ../utilities/blocksearch.sql | Normalizes the (from, to) block range (shared with block-search) |

## Related Processing

Transaction statistics are populated by `process_transaction_stats()` during block processing.

See [processing/transactions.md](../processing/transactions.md).

### Processing Tables

| Table | Populated By | Purpose |
|-------|--------------|---------|
| `hafbe_app.transaction_stats_by_day` | `process_transaction_stats()` | Daily tx counts |
| `hafbe_app.transaction_stats_by_month` | `process_transaction_stats()` | Monthly tx counts |

## Adding a Transaction Endpoint

1. Create SQL file in `endpoints/transactions/`
2. Add OpenAPI annotation with `Transactions` tag
3. Create helper function if needed
4. Define return type in `endpoints/types/transactions.sql`
5. Add URL rewrite to `endpoints/rewrite_rules.conf`
6. Update this documentation

## Potential Extensions

Future transaction endpoints could include:
- Transaction lookup by hash
- Transaction operations for a specific transaction
- Transaction fee statistics
