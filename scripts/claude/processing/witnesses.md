# Witness Stats Processing

**Source**: `db/process_witness_stats.sql`
**Function**: `hafbe_app.process_witness_stats(_from INT, _to INT)`

## Purpose

Processes witness-related operations to populate `hafbe_app.current_witnesses` with witness configuration and statistics including URL, price feed, signing key, version, and block production data.

## Operations Processed

| Operation Type | Properties Updated | Description |
|----------------|-------------------|-------------|
| `witness_set_properties` | All properties | Modern witness configuration |
| `witness_update` | url, block_size, signing_key, hbd_interest_rate, account_creation_fee | Legacy witness configuration |
| `feed_publish` | price_feed, bias, feed_updated_at | Price feed updates |
| `pow` | signing_key, created | Initial key from mining |
| `pow2` | signing_key, created | Initial key from updated mining |
| `producer_missed` | missed_blocks | Count of missed blocks |
| Block extensions | version | Witness node software version |

## Table: `hafbe_app.current_witnesses`

| Column | Type | Description |
|--------|------|-------------|
| `witness_id` | INT | Witness account ID (PK) |
| `url` | TEXT | Witness URL/website |
| `price_feed` | FLOAT | Current HIVE/HBD price feed value |
| `bias` | NUMERIC | Price feed bias percentage |
| `feed_updated_at` | TIMESTAMP | When price feed was last published |
| `block_size` | INT | Preferred maximum block size |
| `signing_key` | TEXT | Public signing key for block production |
| `version` | TEXT | Witness node software version |
| `hbd_interest_rate` | INT | Proposed HBD interest rate (basis points) |
| `last_created_block_num` | INT | Most recent block produced |
| `account_creation_fee` | INT | Fee for creating accounts (in HIVE) |
| `missed_blocks` | INT | Cumulative count of missed blocks |
| `created` | TIMESTAMP | When witness was first registered |

## Key Patterns

### Parser Functions

Located in `backend/operation_parsers/witness_stats_parsers.sql`:

| Function | Returns | Purpose |
|----------|---------|---------|
| `parse_witness_set_properties_operation()` | `witness_properties` | All fields from modern format |
| `parse_witness_update_operation()` | `witness_properties` | Fields from legacy format |
| `parse_feed_publish_operation()` | `witness_properties` | Price feed values |
| `parse_pow_witness_properties()` | `witness_properties` | Initial signing key |
| `parse_pow2_witness_properties()` | `witness_properties` | Initial signing key |
| `parse_block_version()` | TEXT | Version from block extensions |

### Signing Key Priority

Signing keys have complex priority rules:

1. **Priority operations** (`witness_update`, `witness_set_properties`): Explicit key updates - LATEST wins
2. **Pow operations** (`pow`, `pow2`): Initial keys - FIRST wins, only used for INSERT

```sql
-- Priority key: For UPDATE operations
signing_key_priority = FIRST_VALUE(
  CASE WHEN op_type_id IN (_op_witness_update, _op_witness_set_properties)
       THEN signing_key END
) OVER w_signing_key_update

-- Pow key: Only for new witness INSERT
signing_key_pow = FIRST_VALUE(
  CASE WHEN op_type_id IN (_op_pow, _op_pow2)
       THEN signing_key END
) OVER w_signing_key_pow
```

The UPDATE clause uses a subquery to prevent pow keys from overwriting existing keys:
```sql
signing_key = COALESCE(
  (SELECT rp2.signing_key_priority FROM resolved_properties rp2 WHERE rp2.witness_id = EXCLUDED.witness_id),
  cw.signing_key
)
```

### Window Functions for Latest Values

Uses "First Non-NULL" pattern to get latest value per witness:

```sql
FIRST_VALUE(field) OVER (
  PARTITION BY witness
  ORDER BY CASE WHEN field IS NOT NULL THEN 0 ELSE 1 END, operation_id DESC
)
```

- Non-NULL values sort first (0 < 1)
- Among non-NULLs, latest operation wins (DESC)

### Additive Missed Blocks

Missed blocks use additive UPSERT (counts accumulate across batches):

```sql
INSERT INTO hafbe_app.current_witnesses AS cw (witness_id, missed_blocks)
SELECT ... missed_blocks
ON CONFLICT DO UPDATE SET
  missed_blocks = COALESCE(cw.missed_blocks, 0) + EXCLUDED.missed_blocks
```

## Data Flow

### Section 1: Property Updates
```
witness_prop_op_view (operations with witnesses)
    │
    └── all_property_ops CTE (MATERIALIZED)
            │
            └── parsed_properties CTE (parser functions)
                    │
                    └── latest_properties CTE (window functions)
                            │
                            └── resolved_properties CTE (account ID lookup)
                                    │
                                    └── UPSERT into current_witnesses
```

### Section 2: Version Updates
```
blocks_view (blocks with extensions)
    │
    └── parse_block_version()
            │
            └── UPDATE current_witnesses
```

### Section 3: Missed Blocks
```
operations_view (producer_missed ops)
    │
    └── count_missed CTE
            │
            └── ADDITIVE UPSERT into current_witnesses
```

### Section 4: Last Created Block
```
blocks_view (all blocks in range)
    │
    └── MAX(block_num) per witness
            │
            └── UPDATE current_witnesses
```

## How to Modify

### Adding a new witness property

1. Add column to `hafbe_app.current_witnesses` in `hafbe_app.sql`
2. Add field to `hafbe_backend.witness_properties` type
3. Update relevant parser functions to extract the field
4. Add window function in `latest_properties` CTE
5. Include in INSERT and UPDATE SET clauses

### Adding a new operation type

1. Add operation type constant to `backend/utilities/operation_types.sql`
2. Create parser function in `backend/operation_parsers/witness_stats_parsers.sql`
3. Add CASE branch in `parsed_properties` CTE
4. Include operation type ID in `all_property_ops` WHERE filter

## Testing

Witness stats changes can be tested via:
- `tests/regression/` - Compare against hived snapshots
- `tests/tavern/patterns-mainnet/` - API endpoint tests for witness data
