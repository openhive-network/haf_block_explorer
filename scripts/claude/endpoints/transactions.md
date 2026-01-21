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

Returns array of `hafbe_backend.transaction_stats`:
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
- `date` - Period start date
- `trx_count` - Total transactions in period
- `avg_trx` - Average transactions per block
- `min_trx` - Minimum transactions in a block
- `max_trx` - Maximum transactions in a block
- `last_block_num` - Last block in the period

#### Examples

```bash
# Get yearly transaction stats
curl "http://localhost:3000/hafbe-api/transaction-statistics"

# Get monthly stats
curl "http://localhost:3000/hafbe-api/transaction-statistics?granularity=monthly"

# Get daily stats for a specific range
curl "http://localhost:3000/hafbe-api/transaction-statistics?granularity=daily&from-block=2020-01-01%2000:00:00&to-block=2020-12-31%2023:59:59"

# Sort oldest first
curl "http://localhost:3000/hafbe-api/transaction-statistics?direction=asc"
```

## Return Types

Defined in `endpoints/types/transactions.sql`:

| Type | Description |
|------|-------------|
| `hafbe_backend.transaction_stats` | Transaction aggregation record |
| `hafbe_backend.granularity` | Enum: `daily`, `monthly`, `yearly` |

## Implementation Details

### Data Source

Transaction statistics are pre-aggregated in processing and stored in:
- `hafbe_app.transaction_stats_by_day` - Daily aggregations
- `hafbe_app.transaction_stats_by_month` - Monthly aggregations

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
| `get_transaction_aggregation()` | transaction_stats.sql | Query aggregated stats |

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
- Operation type distribution over time
