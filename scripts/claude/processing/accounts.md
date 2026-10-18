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

## Table: `hafbe_app.wallet_stats_by_day`

| Column | Type | Description |
|--------|------|-------------|
| `day` | DATE | Day the accounts were created (PK) |
| `new_wallets` | INT | Accounts whose `account_parameters.created` falls on that day |

A cache of `COUNT(*) ... GROUP BY created::DATE` over `account_parameters`, read by
`/total_wallet_addresses` instead of scanning the 2.6M-row table. It is written in
the same statement that sets `created` (the account-creation upsert in
`process_account_stats()`), so it is maintained in both MASSIVE and LIVE stages and
needs no separate backfill at the end of massive sync. It is a registered table, so
a fork rollback reverts it with `account_parameters`.

The upsert's `RETURNING ap.account, ap.created` gives the post-statement values; a
`NOT EXISTS` against `account_parameters` in a sibling CTE reads the statement
snapshot (pre-upsert values). An account counts when `created` ends non-NULL and was
NULL or absent before. Any new path that sets `created` must count it the same way.

`db/hafbe_app.sql` creates the table in its own DO block (not the context-creation
block), so reinstalling over an existing context creates it and backfills it from
`account_parameters`. The backfill runs before `hive.app_register_table` (so the rows
are not logged as a change of the context's current block) and gives each row a
negative `hive_rowid` (rows present at registration would otherwise all get 0, and
HAF reverts address rows by `hive_rowid`).

`tests/regression` checks it: `hafbe_test.compare_wallet_stats()` recomputes the
aggregate and lists differing days in `hafbe_test.differing_wallet_days`; it can be
run at any block, including after a fork rollback.

## Table: `hafbe_app.account_ops_count`

| Column | Type | Description |
|--------|------|-------------|
| `account_id` | INT | Account ID (PK) |
| `ops_count` | INT | Newest `account_op_seq_no + 1` of the account's operations |

Read by `hafbe_backend.get_account_ops_count()` (`/accounts/{a}`), so the endpoint
never plans against `hafd.account_operations`: the first plan of a query on that
table in a backend opens every 1 GB segment file of the table and its indexes
(about 5 ms at full scale), and every new pgbouncer server connection pays it again.
Accounts without operations have no row (NULL, as before).

Maintained by `db/process_account_ops_count.sql`:

- `process_account_ops_count(_from, _to)` runs in `massive_processing()` and
  `single_processing()` and adds, per account, the number of the range's operations
  that `hive.get_impacted_accounts()` returns it for: HAF writes one
  `account_operations` row per such pair (checked on the 5M-block HAF: identical for
  all 92,462 accounts). `hafd.account_operations` has no index by block, so the
  range cannot be read from it. It does nothing while the context is not forking:
  decoding every operation costs about 2 us, hours over the whole chain.
- `finalize_account_ops_count(_last_block)` sets every account's count from one
  backward probe of `hafd.account_operations`' `(account_id, account_op_seq_no)`
  index (`account_ops_counts_until()`; through the context's
  `account_operations_view` the planner sorts all of an account's rows instead, so
  the bound must be an irreversible block). `log_and_process_blocks()`
  calls it on the first LIVE block, before `hive.app_context_set_forking()` (as the
  balance tracker's finalization: no shadow rows), up to the block before; and
  `create_hafbe_indexes()` up to the context's block, for a sync finished from
  outside the main loop (CI). A no-op once the context is forking.

Like `wallet_stats_by_day`, the table is created in its own DO block, so a
reinstall over an existing context gets it. For a forking context the block fills it
to the irreversible block, adds the context's reversible blocks with
`process_account_ops_count()`, gives the rows negative `hive_rowid`s and only then
registers it; a fork that reverts a block processed before that reinstall does not
revert those rows. A context still in its initial massive sync is left to
`finalize_account_ops_count()`.

`tests/regression` checks it: `hafbe_test.compare_account_ops_count()` recomputes the
newest `account_op_seq_no + 1` per account from the context's view and lists
differences in `hafbe_test.differing_ops_counts`; after LIVE blocks and after a fork
rollback too.

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
                ON CONFLICT DO UPDATE RETURNING account, created
                    │
                    └── new_wallets_by_day CTE (created newly set, per day)
                            │
                            └── UPSERT into wallet_stats_by_day (additive)
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
