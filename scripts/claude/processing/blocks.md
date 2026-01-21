# Block Operations Processing

**Source**: `db/process_block_operations.sql`
**Function**: `hafbe_app.process_block_operations(_from INT, _to INT)`

## Purpose

Aggregates operation counts per block and operation type. This pre-computed data enables fast API queries for block statistics and operation filtering.

## Table: `hafbe_app.block_operations`

| Column | Type | Description |
|--------|------|-------------|
| `block_num` | INT | Block number containing the operations |
| `op_type_id` | INT | Operation type ID (from hive.operation_types) |
| `op_count` | INT | Count of this operation type in the block |

## Implementation

This is the simplest processor - it's a straightforward aggregation:

```sql
WITH operations AS (
  SELECT
    block_num,
    op_type_id,
    COUNT(*) AS op_count
  FROM hafbe_app.operations_view
  WHERE block_num BETWEEN _from AND _to
  GROUP BY block_num, op_type_id
  ORDER BY block_num, op_type_id
)
INSERT INTO hafbe_app.block_operations (block_num, op_type_id, op_count)
SELECT block_num, op_type_id, op_count
FROM operations;
```

## Data Flow

```
hafbe_app.operations_view
    │
    └── GROUP BY block_num, op_type_id
            │
            └── COUNT(*)
                    │
                    └── INSERT INTO block_operations
```

## Indexes

Created by `create_hafbe_indexes()` when transitioning to LIVE mode:

```sql
CREATE INDEX block_operations_block_num ON hafbe_app.block_operations (block_num);
CREATE UNIQUE INDEX block_operations_op_type_id_block_num ON hafbe_app.block_operations (op_type_id, block_num);
```

## Usage by API

This table powers several API endpoints:

| Endpoint | Usage |
|----------|-------|
| `get_op_count_in_block()` | Filter by block_num |
| `get_block()` | Include operation counts in block details |
| Block search | Filter blocks by operation type |

## How to Modify

### Tracking additional aggregations

If you need to track additional per-block statistics:

1. Add column to `hafbe_app.block_operations` table in `hafbe_app.sql`
2. Modify the aggregation query in `process_block_operations()`
3. Update any indexes needed for the new column

### Performance considerations

- This processor scans all operations in the block range
- The `operations_view` is a HAF-provided view that respects app context
- GROUP BY is efficient due to HAF's partitioning scheme
- Inserting is bulk (no UPSERT needed - each block processed once)

## Testing

Block operations changes can be tested via:
- `tests/regression/` - Compare against hived snapshots
- `tests/tavern/patterns-mainnet/` - API tests for block endpoints
