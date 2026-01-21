# Block Search Endpoints

Block search endpoints allow querying blocks by operation types, account filters, and time/block ranges.

## Endpoints

### GET /block-search

**Function:** `hafbe_endpoints.get_block_by_op`
**File:** `endpoints/block-search/get_block_by_op.sql`

Search for blocks containing specific operation types, optionally filtered by account and block range.

#### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `operation-types` | TEXT | No | NULL | Comma-separated operation type IDs (e.g., `18,12`) |
| `account-name` | TEXT | No | NULL | Filter by account that created operations |
| `page` | INT | No | NULL | Page number |
| `page-size` | INT | No | 100 | Results per page (max 1000) |
| `direction` | sort_direction | No | desc | Sort order (`asc`/`desc`) |
| `from-block` | TEXT | No | NULL | Lower bound (block num or timestamp) |
| `to-block` | TEXT | No | NULL | Upper bound (block num or timestamp) |
| `path-filter` | TEXT[] | No | NULL | Filter by operation body path (e.g., `value.creator=alpha`) |

#### Response

Returns `hafbe_backend.block_history`:
```json
{
  "total_blocks": 5000000,
  "total_pages": 1000000,
  "block_range": {
    "from": 1,
    "to": 5000000
  },
  "blocks_result": [
    {
      "block_num": 5000000,
      "created_at": "2016-09-15T19:47:21",
      "producer_account": "ihashfury",
      "producer_reward": "3003845513",
      "trx_count": 2,
      "hash": "004c4b40245ffb07380a393fb2b3d841b76cdaec",
      "prev": "004c4b3fc6a8735b4ab5433d59f4526e4a042644",
      "operations": [
        {"op_type_id": 5, "op_count": 1},
        {"op_type_id": 64, "op_count": 1}
      ]
    }
  ]
}
```

#### Examples

```bash
# Get latest 5 blocks
curl "http://localhost:3000/hafbe-api/block-search?page-size=5"

# Filter by operation type (vote operations = type 0)
curl "http://localhost:3000/hafbe-api/block-search?operation-types=0&page-size=10"

# Filter by account and block range
curl "http://localhost:3000/hafbe-api/block-search?account-name=blocktrades&from-block=4000000&to-block=5000000"

# Filter by timestamp range
curl "http://localhost:3000/hafbe-api/block-search?from-block=2016-09-01%2000:00:00&to-block=2016-09-15%2023:59:59"

# Use path filter (requires extra indexes)
curl "http://localhost:3000/hafbe-api/block-search?operation-types=78&path-filter=value.creator=alpha"
```

## Implementation Details

### Block Range Conversion

The `from-block` and `to-block` parameters accept either:
- Block numbers (integers)
- Timestamps (format: `YYYY-MM-DD HH:MI:SS`)

Conversion is handled by `hive.convert_to_blocks_range()`:
- For `from-block`: finds first block where `created_at >= timestamp`
- For `to-block`: finds first block where `created_at <= timestamp`

### Path Filters

Path filters allow searching within operation bodies. This requires:
1. Extra indexes to be installed (validated by `validate_block_search_indexes()`)
2. A single operation type specified

Filter format: `value.<path>=<value>`

### Caching

- Historical data (to_block <= irreversible): `max-age=31536000`
- Live data: `max-age=2`

## Helper Functions

Located in `backend/endpoint_helpers/blocksearch.sql`:

| Function | Purpose |
|----------|---------|
| `get_blocks_by_ops()` | Core query logic |
| `validate_block_search_indexes()` | Check path filter indexes |
| `validate_single_operation_type()` | Ensure single op type for path filter |
| `validate_path_filter_keys()` | Validate path filter syntax |

## Related Processing

Block operation counts are populated by `process_block_operations()`. See [processing/blocks.md](../processing/blocks.md).

## Adding Path Filter Support

To add path filter support for a new operation type:

1. Create the required indexes
2. Add the operation type to the validation in `validate_path_filter_keys()`
3. Test with the new operation type
