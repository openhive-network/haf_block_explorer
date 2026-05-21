# HAFBE Processing & Synchronization

This document covers how HAFBE processes blockchain data from HAF.

## Overview

HAFBE processes blocks from HAF (Hive Application Framework) via a main loop that runs continuously. The entry point is `hafbe_app.main()` called by `scripts/process_blocks.sh`.

**Processing pipeline:**
1. `scripts/process_blocks.sh` starts the application
2. `hafbe_app.main()` enters an infinite loop calling `hive.app_next_iteration()`
3. For each block range, `log_and_process_blocks()` orchestrates:
   - Balance Tracker processing (btracker)
   - HAFBE core processing (5 processors)
   - HAF state provider updates

## Processing Stages

HAFBE uses two synchronization stages defined in `db/hafbe_app.sql`:

### MASSIVE_PROCESSING (Bulk Sync)

- **When**: Initial sync or catching up after downtime
- **Batch size**: 10,000 blocks per iteration
- **Optimization**: `synchronous_commit = OFF` for throughput
- **Behavior**: No cache tables, indexes created after stage completes

### LIVE Mode

- **When**: Caught up with blockchain head
- **Batch size**: 1 block per iteration
- **Optimization**: `synchronous_commit = ON` for data safety
- **Behavior**: Updates cache tables, indexes already exist

**Stage detection:**
```sql
SELECT hive.get_current_stage_name('hafbe_app');  -- Returns 'MASSIVE_PROCESSING' or 'LIVE'
```

## Processing Functions Inventory

All processing functions are in `db/process_*.sql` files.

| Function | File | Purpose |
|----------|------|---------|
| `process_blocks()` | `hafbe_app.sql` | Dispatcher - routes to massive or single processing |
| `massive_processing()` | `hafbe_app.sql` | Processes block ranges during bulk sync |
| `single_processing()` | `hafbe_app.sql` | Processes individual blocks in live mode |
| `process_account_stats()` | `process_account_stats.sql` | Account creation, recovery, voting rights |
| `process_block_operations()` | `process_block_operations.sql` | Op counts per block + daily/monthly per-op-type rollups (single scan, three sinks) |
| `process_transaction_stats()` | `process_transaction_stats.sql` | Daily/monthly transaction aggregations |
| `process_witness_stats()` | `process_witness_stats.sql` | Witness properties and metadata |
| `process_witness_votes()` | `process_witness_votes.sql` | Witness votes and proxy assignments |
| `process_witness_votes_cache()` | `process_witness_votes.sql` | Cache refresh (LIVE only) |
| `process_proposals()` | `process_proposals.sql` | UNIFIED processor for ALL proposal ops — create (paired with virtual proposal_fee for id capture) / update / remove / pay / update_proposal_votes / declined_voting_rights / expired_account. Uses an explicit FOR loop (not CTE+CASE) because operation ordering is safety-critical: remove-then-vote sequences in the same batch must not insert votes after the cascade. |
| `process_proposal_vote_stats_cache()` | `process_proposal_votes.sql` | Stake-weighted proposal vote totals (LIVE only; mirrors witness cache pattern, runs after `process_witness_votes_cache` so account_vest_stats_cache is fresh) |

### Processing Order

Each block range calls processors in this order:
1. `process_account_stats()` - Account parameters
2. `process_block_operations()` - Op counts per block + per-day/month per-op-type rollups
3. `process_transaction_stats()` - Transaction aggregations
4. `process_witness_stats()` - Witness metadata
5. `process_witness_votes()` - Vote and proxy state
6. `process_proposals()` - All proposal ops in one row-by-row processor: create/update/remove/pay + update_proposal_votes + decline/expired cleanup

In LIVE mode, two cache refreshes run after the processors (in this order):
- `process_witness_votes_cache()` - rebuilds `account_vest_stats_cache` + witness vote caches
- `process_proposal_vote_stats_cache()` - rebuilds `proposal_vote_stats_cache` (depends on the fresh `account_vest_stats_cache`)

## Submodule Processing

HAFBE delegates some processing to integrated submodules:

### Balance Tracker (btracker)
- **Called via**: `btracker_process_blocks()` in `log_and_process_blocks()`
- **Purpose**: Account balances (HIVE, HBD, VESTS, savings, delegations)
- **Schema**: `hafbe_bal`
- **Docs**: `submodules/btracker/scripts/claude/`

### Reputation Tracker (reptracker)
- **Integration**: Separate HAF app with own processing loop
- **Purpose**: Account reputation scores from votes
- **Schema**: `reptracker_app`
- **Docs**: `submodules/reptracker/scripts/claude/`

### HAfAH (hafah)
- **Integration**: Uses HAF state providers, no custom processing
- **Purpose**: Account operation history
- **Docs**: `submodules/hafah/CLAUDE.md` (basic documentation only - no modular docs)

## Control Functions

Located in `db/hafbe_app.sql`:

| Function | Purpose |
|----------|---------|
| `allowProcessing()` | Enable processing (called at startup) |
| `stopProcessing()` | Signal graceful shutdown |
| `continueProcessing()` | Check if should continue (polled in loop) |

**Graceful shutdown:**
```sql
-- From another session:
SELECT hafbe_app.stopProcessing();
COMMIT;  -- Must commit for change to be visible
```

## Detailed Documentation

For implementation details of each processor:

| Processor | Documentation |
|-----------|---------------|
| Account Stats | [processing/accounts.md](processing/accounts.md) |
| Witness Stats | [processing/witnesses.md](processing/witnesses.md) |
| Witness Votes | [processing/witness_votes.md](processing/witness_votes.md) |
| Block Operations | [processing/blocks.md](processing/blocks.md) |
| Transaction Stats | [processing/transactions.md](processing/transactions.md) |

## Key Tables

### Core Processing Tables
| Table | Populated By | Purpose |
|-------|--------------|---------|
| `hafbe_app.account_parameters` | `process_account_stats()` | Account metadata |
| `hafbe_app.block_operations` | `process_block_operations()` | Op counts per block |
| `hafbe_app.transaction_stats_by_day` | `process_transaction_stats()` | Daily tx stats |
| `hafbe_app.transaction_stats_by_month` | `process_transaction_stats()` | Monthly tx stats |
| `hafbe_app.operation_type_stats_by_day` | `process_block_operations()` | Daily per-op-type counts |
| `hafbe_app.operation_type_stats_by_month` | `process_block_operations()` | Monthly per-op-type counts |
| `hafbe_app.current_witnesses` | `process_witness_stats()` | Witness properties |
| `hafbe_app.witness_votes_history` | `process_witness_votes()` | Vote change log |
| `hafbe_app.current_witness_votes` | `process_witness_votes()` | Active votes |
| `hafbe_app.account_proxies_history` | `process_witness_votes()` | Proxy change log |
| `hafbe_app.current_account_proxies` | `process_witness_votes()` | Active proxies |
| `hafbe_app.proposal_votes_history` | `process_proposals()` | Proposal vote change log (includes synthetic `approve=FALSE` rows from remove/decline cascades) |
| `hafbe_app.current_proposal_votes` | `process_proposals()` | Currently active proposal approvals |
| `hafbe_app.current_proposals` | `process_proposals()` | Proposal metadata mirror (create/update/remove); `paid_amount` column is a running total incremented by each `proposal_pay_operation` |
| `hafbe_app.proposal_payments` | `process_proposals()` | Append-only per-payment audit ledger from `proposal_pay_operation` |

### Cache Tables (LIVE only)
| Table | Purpose |
|-------|---------|
| `hafbe_app.account_vest_stats_cache` | Vesting power per account |
| `hafbe_app.witness_votes_cache` | Total votes per witness |
| `hafbe_app.witness_rank_cache` | Witness rankings |
| `hafbe_app.witness_votes_change_cache` | 24h vote changes |
| `hafbe_app.proposal_vote_stats_cache` | Stake-weighted proposal totals + voters_num |

## Expansion Rules

When adding a new processor:

1. Create the SQL file in `db/process_<name>.sql`
2. Add call to `massive_processing()` and `single_processing()` in `hafbe_app.sql`
3. Create documentation at `scripts/claude/processing/<name>.md`
4. Update this index with link and one-line description
5. Add any new tables to the Key Tables section

When modifying existing processors:

1. Update the corresponding `db/process_*.sql` file
2. Update detailed docs in `scripts/claude/processing/`
3. If adding new tables, register with `hive.app_register_table()`
