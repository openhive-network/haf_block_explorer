# HAFBE Processing & Synchronization

This document covers how HAFBE processes blockchain data from HAF.

## Overview

HAFBE processes blocks from HAF (Hive Application Framework) via a main loop that runs continuously. The entry point is `hafbe_app.main()` called by `scripts/process_blocks.sh`.

**Processing pipeline:**
1. `scripts/process_blocks.sh` starts the application (see "Which loop runs" below)
2. `hafbe_app.main()` enters an infinite loop calling `hive.app_next_iteration()`
3. For each block range, `log_and_process_blocks()` orchestrates:
   - Balance Tracker processing (btracker)
   - HAFBE core processing (5 processors)
   - HAF state provider updates

## Which loop runs

haf_block_explorer registers in the HAF application registry (`hafd.applications`, haf#341) as `haf_block_explorer`, the name it locks (`--lock=haf_block_explorer`): HAF's lock helpers (`hive._app_broken_reason`, haf#454; `hive._missing_app_process_procedure` before it, haf#403) find the row by the lock name. Its group holds the context `hafbe_app` (the context name is unchanged) and the embedded balance tracker's. `db/hafbe_app.sql` unregisters whatever other row holds the balance tracker's context (found by context, not by name) before it registers, and refuses (install exits non-zero) a row holding `hafbe_app` under another name, e.g. one left as `hafbe_app` by an install older than the rename: replay from scratch, or `SELECT hive.app_unregister('hafbe_app');` and reinstall. Re-registering over `haf_block_explorer` keeps its `paused` flag.

`scripts/process_blocks.sh` asks the registry before it starts anything; `haf_app_driver.py` being on PATH (the psql base image ships it) is not enough, since the driver exits before its first range when the registry cannot run the app:

| Registry state | process_blocks.sh |
|---|---|
| `haf_block_explorer` registered, `process_procedure` (`hafbe_app.process_blocks`) exists | `exec haf_app_driver.py --app=haf_block_explorer --lock=haf_block_explorer` (the legacy loop when the binary is missing) |
| `haf_block_explorer` registered, procedure NULL or gone | exit 1, "Reinstall haf_block_explorer" |
| a row named `hafbe_app` holds the `hafbe_app` context | exit 1, replay or unregister `hafbe_app` and reinstall |
| another application's `contexts` hold `hafbe_app` | exit 1, no second loop |
| nothing registered for `hafbe_app` (no registry: HAF 1.28.6 and older) | legacy `CALL hafbe_app.main(...)` loop |
| cannot connect | retried `REGISTRY_PROBE_ATTEMPTS` (12) times, `REGISTRY_PROBE_RETRY_SECONDS` (5 s) apart, then exit 1 for the restart policy |
| registry query fails on a live connection | exit 1 |

The driver runs the whole group (`hafbe_app` + the embedded balance tracker context). On a HAF without the registry `db/hafbe_app.sql` skips `hive.app_register` with a WARNING, and `main()` runs without `hive.acquire_app_block_processor_locks` (WARNING) when HAF has no lock helpers. Tested by `tests/process_blocks_selection/run_test.sh` (see tests.md).

## Processing Stages

HAFBE uses two synchronization stages defined in `db/hafbe_app.sql`:

### MASSIVE_PROCESSING (Bulk Sync)

- **When**: Initial sync or catching up after downtime
- **Batch size**: 10,000 blocks per iteration
- **Optimization**: `synchronous_commit = OFF` for throughput
- **Behavior**: No cache tables, indexes created after stage completes
- **Not only the initial sync**: HAF re-enters this stage for any catch-up of
  more than 101 blocks (restart, stack switch, slow live processing). Work that
  is only meant for the genesis replay must key off `NOT isIndexesCreated()`,
  not the stage name. `process_blocks()` does this for the `VACUUM` request on
  the `current_*` tables: HAF runs it as `VACUUM FULL ANALYZE` under an ACCESS
  EXCLUSIVE lock, which is fine once over a replay but stalled every
  post-restart catch-up (see balance_tracker#64 for the same pattern)

### LIVE Mode

- **When**: Caught up with blockchain head
- **Batch size**: 1 block per iteration
- **Optimization**: `synchronous_commit = ON` for data safety
- **Behavior**: Updates cache tables, indexes already exist

### Visibility map after the massive sync

hafbe keeps its indexes and never calls `hive.app_restore_indexes()`, so HAF
queues no freeze for it: `request_tables_freeze()` queues one `'freeze'` vacuum
request (`VACUUM (FREEZE, ANALYZE)`, run by hived after the transaction commits)
for every table the massive sync writes except the `current_*` tables (VACUUM
FULLed during the sync) and the LIVE-only caches. `log_and_process_blocks()`
calls it on the first LIVE block, after `finalize_account_ops_count()` and the
balance tracker's finalization; `create_hafbe_indexes()` calls it for a sync
finished outside the main loop (CI). Both only while the context is not forking
yet, i.e. once. On a HAF without request kinds (before haf#360) it skips with a
NOTICE.

The insert-only and insert-mostly tables (`block_operations`, the `*_history`
tables, the `*_stats_by_day` tables, `wallet_stats_by_day`,
`account_ops_count`) are created with `autovacuum_vacuum_insert_scale_factor =
0.005` and `autovacuum_freeze_min_age = 0` (`account_ops_count` also with
`autovacuum_vacuum_scale_factor = 0.01`), so autovacuum keeps them all-visible
and frozen while live. Install only: an existing table keeps its reloptions.

**Stage detection:**
```sql
SELECT hive.get_current_stage_name('hafbe_app');  -- Returns 'MASSIVE_PROCESSING' or 'LIVE'
```

### Starting while hived replays (early block processing)

The install opts both contexts of the group (`hafbe_app` and the balance
tracker's `hafbe_bal`) in with `hive.app_context_set_early_block_processing`
(last block of `db/hafbe_app.sql`; skipped with a NOTICE on a HAF before haf#379).
When hived runs with `psql-massive-index-policy = keep-monotonic`,
`hive.app_next_iteration` then delivers irreversible blocks while hived still
replays, with HAF's `defer` core indexes missing. With the default `drop-all`
policy nothing changes.

- **Block processing reads only `keep` indexes**: every `process_*` function
  selects operations by `block_num` plus an operation-id range (`pk_hive_operations`
  / `hive_operations_block_num_id_idx`), transactions by `block_num`
  (`hive_transactions_block_num_trx_in_block_idx`), and blocks by `num` range
  (`pk_hive_blocks`; the per-producer stats group the range by
  `producer_account_id`, they never look a producer up). Nothing reads by
  `trx_hash`, by operation type without a block range, or through an expression
  index on operation bodies. Account names are resolved through `accounts_view`
  (`hafd.accounts` indexes: still `defer` on HAF develop 78c84a95; haf#381 moves
  them to `keep`, hafbe does not wait for them).
- **`hafd.account_operations`** is read only by `finalize_account_ops_count()`, at
  the first LIVE block (and from `create_hafbe_indexes()`). It calls
  `hive.wait_for_core_indexes(<group>, 'hafd.account_operations', NULL, '6 hours')`
  first: hived rebuilds that table with `CLUSTER` when the replay ends.
  `log_and_process_blocks()` calls it first in that transaction, before the
  balance tracker's finalization writes anything.
  `process_account_ops_count()` does nothing until the context is forking, and
  reads `operations_view` by block range when it does.
- **The massive sync cannot end early**: the stage comes from
  `hive.app_next_iteration`, which compares the context's block with
  `hive.get_estimated_hive_head_block()` (the real chain head), not with hived's
  irreversible head, so the group stays in `MASSIVE_PROCESSING` while hived
  replays. Everything that ends the massive sync (`create_hafbe_indexes()`, the
  account_ops_count fill, the balance tracker's finalization, the switch to
  forking) runs on the first LIVE iteration.
- **Test**: `tests/early_block_processing/run_test.sh` (see `tests.md`).

## Processing Functions Inventory

All processing functions are in `db/process_*.sql` files.

| Function | File | Purpose |
|----------|------|---------|
| `process_blocks()` | `hafbe_app.sql` | Dispatcher - routes to massive or single processing |
| `massive_processing()` | `hafbe_app.sql` | Processes block ranges during bulk sync |
| `single_processing()` | `single_processing.sql` | Processes individual blocks in live mode (installed after the `process_*.sql` files it calls) |
| `process_account_stats()` | `process_account_stats.sql` | Account creation, recovery, voting rights |
| `process_account_ops_count()` | `process_account_ops_count.sql` | Operation count per account (forking context only; `finalize_account_ops_count()` fills it at the end of massive sync) |
| `process_block_operations()` | `process_block_operations.sql` | Op counts per block + daily/monthly per-op-type rollups (single scan, three sinks) |
| `process_transaction_stats()` | `process_transaction_stats.sql` | Daily/monthly transaction aggregations |
| `process_witness_stats()` | `process_witness_stats.sql` | Witness properties and metadata |
| `process_witness_votes()` | `process_witness_votes.sql` | Witness votes and proxy assignments |
| `process_witness_votes_cache(_block)` | `process_witness_votes.sql` | Witness vote cache refresh per LIVE block: incremental, or the full recompute when the block can change what the caches track or is not the successor of the last refreshed block |
| `process_witness_votes_cache()` | `process_witness_votes.sql` | Full recompute of the witness vote caches (first LIVE entry, CI, mock setup) |
| `process_proposals()` | `process_proposals.sql` | UNIFIED processor for ALL proposal ops — create (paired with virtual proposal_fee for id capture) / update / remove / pay / update_proposal_votes / declined_voting_rights / expired_account. Uses an explicit FOR loop (not CTE+CASE) because operation ordering is safety-critical: remove-then-vote sequences in the same batch must not insert votes after the cascade. `process_proposal_vote_op` only records votes for proposals that currently exist and are not removed — mirroring hived's `update_proposal_votes_evaluator`, which `continue`s past missing/removed proposal_ids. Pre-HF28 the chain accepted (and silently dropped) votes for nonexistent proposals; replaying them without this guard tripped the `current_proposal_votes -> current_proposals` FK and crashed block processing. |
| `process_proposal_vote_stats_cache()` | `process_proposal_vote_stats_cache.sql` | Stake-weighted proposal vote totals (LIVE only; mirrors witness cache pattern, runs after `process_witness_votes_cache` so account_vest_stats_cache is fresh) |

### Processing Order

Each block range calls processors in this order:
1. `process_account_stats()` - Account parameters
   - `process_account_ops_count()` - Operation count per account
2. `process_block_operations()` - Op counts per block + per-day/month per-op-type rollups
3. `process_transaction_stats()` - Transaction aggregations
4. `process_witness_stats()` - Witness metadata
5. `process_witness_votes()` - Vote and proxy state
6. `process_proposals()` - All proposal ops in one row-by-row processor: create/update/remove/pay + update_proposal_votes + decline/expired cleanup

In LIVE mode, two cache refreshes run after the processors (in this order):
- `process_witness_votes_cache(_block)` - updates `account_vest_stats_cache` + witness vote caches from the block's impacted accounts, or recomputes them in full (see [witness_votes.md](processing/witness_votes.md#cache-processing-live-only))
- `process_proposal_vote_stats_cache()` - same for `proposal_vote_stats_cache` (depends on the fresh `account_vest_stats_cache`)

### Why process_proposals uses a FOR LOOP instead of CTE+CASE

Most processors (e.g. `process_witness_votes`) dispatch per-op handlers via a
`WITH ... SELECT CASE` pattern where the planner evaluates the CASE expressions
in ORDER BY id sequence. PostgreSQL does not formally guarantee that
side-effecting functions in a SELECT list fire in ORDER BY order — it works in
practice but is a planner assumption, not a spec guarantee.

For proposal processing the ordering invariant is safety-critical: a
remove-then-vote sequence arriving in the same MASSIVE batch must not insert a
vote row after the remove cascade has already deleted the proposal's votes.
An explicit PL/pgSQL `FOR` loop iterates in the cursor's `ORDER BY id` sequence
by definition, so the guarantee is structural rather than planner-dependent.
`process_witness_votes` keeps the CTE+CASE pattern (accepted assumption already
in production); `process_proposals` uses the loop where the stakes are higher.

## Submodule Processing

HAFBE delegates some processing to integrated submodules:

### Balance Tracker (btracker)
- **Called via**: `btracker_process_blocks()` in `log_and_process_blocks()`
- **Purpose**: Account balances (HIVE, HBD, VESTS, savings, delegations)
- **Schema**: `hafbe_bal`
- **Finalization**: on the first LIVE block `log_and_process_blocks()` calls
  btracker's `finalize_massive_sync_before_forking()` before switching both
  contexts to forking. Besides backfilling the rollups, it sets the history
  tables back to LOGGED and queues one `'freeze'` vacuum request
  (`VACUUM (FREEZE, ANALYZE)`) per history table, or none with a NOTICE on a HAF
  without request kinds. The tables' insert-only autovacuum reloptions are set
  at install
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
| `hafbe_app.wallet_stats_by_day` | `process_account_stats()` | Accounts created per day |
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
| `hafbe_app.current_proposals` | `process_proposals()` | Proposal metadata mirror (create/update/remove); `paid_amount` column is a running total incremented by each `proposal_pay_operation` (no per-payment ledger: HAF's fork revert of `current_proposals` keeps the total exact) |

### Cache Tables (LIVE only)
| Table | Purpose |
|-------|---------|
| `hafbe_app.account_vest_stats_cache` | Vesting power per account — current voters/proxies/proposal voters, **plus** anyone with a witness vote event in the daily-change window (issue #142) |
| `hafbe_app.witness_votes_cache` | Total votes per witness |
| `hafbe_app.witness_rank_cache` | Witness rankings |
| `hafbe_app.witness_votes_change_cache` | 24h vote changes |
| `hafbe_app.proposal_vote_stats_cache` | Stake-weighted proposal totals + voters_num |

## Expansion Rules

When adding a new processor:

1. Create the SQL file in `db/process_<name>.sql`
2. Add call to `massive_processing()` in `hafbe_app.sql` and to `single_processing()` in `single_processing.sql`
   (install_app.sh installs `single_processing.sql` after every `process_*.sql`, so an
   interrupted install never leaves it calling a function that does not exist yet)
3. Create documentation at `scripts/claude/processing/<name>.md`
4. Update this index with link and one-line description
5. Add any new tables to the Key Tables section

When a change retires a table that the previously installed processing code still
writes, drop it in a `db/` file that install_app.sh applies after the processing
functions (as `drop_proposal_payments.sql` does), not in `hafbe_app.sql`, and keep the
drop idempotent.

When modifying existing processors:

1. Update the corresponding `db/process_*.sql` file
2. Update detailed docs in `scripts/claude/processing/`
3. If adding new tables, register with `hive.app_register_table()`
