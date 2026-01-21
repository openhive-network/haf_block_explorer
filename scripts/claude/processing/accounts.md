# Account Stats Processing

**Source**: `db/process_account_stats.sql`
**Function**: `hafbe_app.process_account_stats(_from INT, _to INT)`

## Purpose

Processes account-related operations to populate `hafbe_app.account_parameters` with:
- Account creation info (mined, created timestamp)
- Recovery account tracking
- Voting rights status
- Account creation token balance

## Operations Processed

| Operation Type | Field Updated | Description |
|----------------|---------------|-------------|
| `pow` | mined, created | Original proof-of-work mining |
| `pow2` | mined, created | Updated PoW format |
| `account_created` | recovery_account, created | Virtual op with authoritative timestamp |
| `account_create` | mined, created | Fee-based account creation |
| `create_claimed_account` | mined, created | Token-based account creation |
| `account_create_with_delegation` | mined, created | Account creation with delegation |
| `changed_recovery_account` | recovery_account | User changing recovery |
| `recover_account` | last_account_recovery | Account recovery event |
| `decline_voting_rights` | can_vote | User declining/regaining voting rights |
| `claim_account` | pending_claimed_accounts | +1 token |
| `create_claimed_account` | pending_claimed_accounts | -1 token |

## Table: `hafbe_app.account_parameters`

| Column | Type | Description |
|--------|------|-------------|
| `account` | INT | Account ID (FK to hive.accounts_view) |
| `can_vote` | BOOLEAN | FALSE if decline_voting_rights was set |
| `mined` | BOOLEAN | TRUE if account was created via PoW mining |
| `recovery_account` | TEXT | Designated recovery account name |
| `last_account_recovery` | TIMESTAMP | When account was last recovered |
| `created` | TIMESTAMP | Account creation timestamp |
| `pending_claimed_accounts` | INT | Unclaimed account creation tokens |

## Key Patterns

### Parser Functions

Located in `backend/operation_parsers/account_operations.sql`:

| Function | Returns | Purpose |
|----------|---------|---------|
| `parse_pow_operation()` | `impacted_account_parameters` | Extract from pow ops |
| `parse_pow2_operation()` | `impacted_account_parameters` | Extract from pow2 ops |
| `parse_account_created_operation()` | `impacted_account_parameters` | Extract with HF11 logic |
| `parse_account_create_operation()` | `impacted_account_parameters` | Extract from create ops |
| `parse_changed_recovery_account_operation()` | `impacted_account_parameters` | Extract recovery changes |
| `parse_recover_account_operation()` | `recover_account_result` | Extract recovery events |
| `parse_decline_voting_rights_operation()` | `decline_voting_rights_result` | Extract voting rights |
| `parse_claim_account_operation()` | `claim_account_result` | Extract token claims |

### Hardfork 11 Logic

Pre-HF11 vs post-HF11 affects recovery account defaults:
- **Pre-HF11**: Default recovery = `'steem'`
- **Post-HF11**: Default recovery = creator (unless self-created)

```sql
_hf11_block := (SELECT block_num FROM hafd.applied_hardforks WHERE hardfork_num = 11);
```

### UPSERT Patterns

**Immutable fields** (set once, never overwritten):
```sql
-- mined, created: Existing value takes precedence
mined = COALESCE(ap.mined, EXCLUDED.mined, hafbe_backend.default_mined())
created = COALESCE(ap.created, EXCLUDED.created, hafbe_backend.default_timestamp())
```

**Mutable fields** (updates take effect):
```sql
-- recovery_account: New value takes precedence
recovery_account = COALESCE(EXCLUDED.recovery_account, ap.recovery_account, hafbe_backend.default_recovery_account())
```

**Additive fields** (accumulate over time):
```sql
-- pending_claimed_accounts: Add delta to existing count
pending_claimed_accounts = ap.pending_claimed_accounts + EXCLUDED.pending_claimed_accounts
```

## Data Flow

```
operations_view_extended
    │
    ├── parse_*_operation() functions
    │
    └── parsed_operations CTE (MATERIALIZED)
            │
            ├── final_values CTE (DISTINCT ON + window functions)
            │
            └── INSERT INTO account_parameters
                ON CONFLICT DO UPDATE
```

## How to Modify

### Adding a new account field

1. Add column to `hafbe_app.account_parameters` in `hafbe_app.sql`
2. Create parser function in `backend/operation_parsers/account_operations.sql`
3. Add operation type to the filter in `process_account_stats()`
4. Add to the appropriate CTE chain
5. Include in INSERT/UPDATE statements with correct COALESCE pattern

### Adding a new operation type

1. Add operation type constant to `backend/utilities/operation_types.sql`
2. Create parser function in `backend/operation_parsers/account_operations.sql`
3. Add CASE branch to `parsed_operations` CTE
4. Include operation type ID in WHERE filter

## Testing

Account stats changes can be tested via:
- `tests/regression/` - Compare against hived snapshots
- `tests/tavern/patterns-mainnet/` - API endpoint tests for account data
