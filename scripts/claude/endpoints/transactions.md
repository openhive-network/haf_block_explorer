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
| `from-block` | TEXT | No | NULL | Lower bound (block num or timestamp) |
| `to-block` | TEXT | No | NULL | Upper bound (block num or timestamp) |

#### Response

Returns `SETOF hafbe_backend.transaction_stats` — a **bare array**, one entry per
period. Not paginated, and never range-defaulted: one pre-aggregated row per period
keeps even a full-history `daily` response at ~3,750 rows / ~400 kB.
```json
[
  {
    "date": "2017-01-01T00:00:00",
    "trx_count": 6961192,
    "avg_trx": 1,
    "min_trx": 0,
    "max_trx": 89,
    "last_block_num": 5000000
  }
]
```

**Fields:**
- `date` - Period end date (capped at current time for the in-progress period)
- `trx_count` - Total transactions in period
- `avg_trx` - Average transactions per block
- `min_trx` - Minimum transactions in a block
- `max_trx` - Maximum transactions in a block
- `last_block_num` - Last block in the period

#### Examples

```bash
# Get yearly transaction stats (all periods)
curl "http://localhost:3000/hafbe-api/transaction-statistics"

# Get monthly stats
curl "http://localhost:3000/hafbe-api/transaction-statistics?granularity=monthly"

# Get daily stats for a specific range
curl "http://localhost:3000/hafbe-api/transaction-statistics?granularity=daily&from-block=2020-01-01%2000:00:00&to-block=2020-12-31%2023:59:59"

# Sort oldest first
curl "http://localhost:3000/hafbe-api/transaction-statistics?direction=asc"
```

### GET /operation-type-statistics

**Function:** `hafbe_endpoints.get_operation_type_statistics`
**File:** `endpoints/transactions/get_operation_type_statistics.sql`

Get per-op-type operation counts plus transaction totals for each period. Same
granularity/direction/range model as `/transaction-statistics`, but with a 1-year
default window at `daily` (see Response).

#### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `granularity` | granularity | No | yearly | Aggregation level: `daily`, `monthly`, `yearly` |
| `direction` | sort_direction | No | desc | Sort order (by date) |
| `from-block` | TEXT | No | NULL | Lower bound (block num or timestamp). **Omitted at `daily` => defaults to the last 1 year**, not genesis |
| `to-block` | TEXT | No | NULL | Upper bound (block num or timestamp) |
| `op-types` | TEXT | No | NULL | Comma-separated `op_type_id` filter (e.g. `0,1,18`); NULL = all |

#### Response

Returns `SETOF hafbe_backend.operation_type_stats` — a **bare array**, one entry per
period:
```json
[
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
```

Each entry nests a per-op-type array, so an unbounded `daily` series is ~3,750 periods /
~6.6 MB / ~4.4 s and trips client timeouts (issue #139). When `from-block` is **omitted**
at `daily`, the range therefore falls back to a 1-year window. An explicit `from-block` is
honoured in full at every granularity, and `monthly`/`yearly` are never defaulted.

**Fields:**
- `date` - Period end date (capped at current time for the in-progress period)
- `total_transactions` - Total transactions in the period (always unfiltered by `op-types`)
- `total_operations` - Total operations in the period (sum of `operations[].op_count`; reflects the `op-types` filter when set)
- `operations` - Per-op-type breakdown (`op_type_id`, `op_count`)
- `last_block_num` - Last block in the period

Note: the period count is independent of the `op-types` filter (every period is
one row, even when its filtered breakdown is empty).

#### Examples

```bash
# Yearly per-op-type stats (all 11 periods)
curl "http://localhost:3000/hafbe-api/operation-type-statistics"

# Daily, no range -> most recent 1 year only
curl "http://localhost:3000/hafbe-api/operation-type-statistics?granularity=daily"

# Daily over an explicit range -> honoured in full, only vote (0) and custom_json (18)
curl "http://localhost:3000/hafbe-api/operation-type-statistics?granularity=daily&from-block=1&to-block=5000000&op-types=0,18"
```

## Return Types

Defined in `endpoints/types/transactions.sql`:

| Type | Description |
|------|-------------|
| `hafbe_backend.transaction_stats` | Transaction aggregation record (one period) |
| `hafbe_backend.operation_type_stats` | Per-op-type aggregation record (one period), incl. nested `operations[]` |
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
| `get_transaction_aggregation()` | transactions.sql | Build the transaction-stats series for the range. **Returns rows UNORDERED** -- the endpoint applies the single authoritative `ORDER BY`; any other caller must sort for itself |
| `get_operation_type_aggregation()` | operation_type_stats.sql | Build the per-op-type series for the range. **Returns rows UNORDERED** -- see above |
| `aggregation_time_range()` | ../utilities/blocksearch.sql | Resolve (granularity, block range) to the period-truncated `[from_ts, to_ts]` window |
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
