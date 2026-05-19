# HAFBE Proposal Mock Data

Mock blockchain data for testing HAFBE's proposal processing without waiting
for HAF to sync past block ~22.3M (where DHF launched). Mirrors the btracker
mock framework — see `submodules/btracker/tests/mocks/README.md` for the
underlying pattern.

## Layout

Mirrors btracker's split: the installer only loads fixtures, processing is
done by the standard `process_blocks.sh`, and verification is a separate
step.

```
scripts/
└── verify_mock_data.sh           # refreshes caches + runs verify.sql

tests/mocks/
├── install_mock_data.sh          # loads fixtures + rewinds contexts (no processing)
├── sql/
│   ├── types.sql                 # composite types for json_populate_recordset
│   ├── insert_blocks.sql         # hafbe_backend.insert_mock_blocks(json)
│   ├── insert_operations.sql     # hafbe_backend.insert_mock_operations(json)
│   ├── update_haf_state.sql      # hafbe_backend.update_irreversible_block()
│   └── verify.sql                # PASS/FAIL assertion table
└── fixtures/
    ├── blocks/data.json          # 4 mock block headers (91000001..91000004)
    └── proposals/data.json       # proposal lifecycle ops covering both cascade scenarios
```

Block range: **91000000+** (chosen to NOT collide with btracker's 90000000+
mock range so both can coexist on the same DB).

## Scenario

The fixture sequences these ops to cover the two cascade-cleanup paths
(proposal removal → vote cleanup, and decline_voting_rights → vote cleanup)
that motivated the unified row-by-row processor design:

| Block       | Op | Effect |
|-------------|----|--------|
| `91000001`  | `create_proposal` + `proposal_fee` | proposal **9001** (blocktrades→gtg, 240k) |
| `91000002`  | `create_proposal` + `proposal_fee` | proposal **9002** (blocktrades→gtg, 100k) |
| `91000002`  | `update_proposal_votes`            | **steem** approves [9001, 9002] |
| `91000002`  | `update_proposal_votes`            | **dan** approves [9001] |
| `91000003`  | `update_proposal_operation`        | 9002 daily_pay → 50k |
| `91000003`  | `declined_voting_rights_operation` | **steem** loses voting rights → cascade-deletes steem's votes on [9001, 9002] |
| `91000004`  | `update_proposal_votes`            | **initminer** approves [9001, 9002] |
| `91000004`  | `remove_proposal`                  | removes [9001] → cascade-deletes dan→9001 AND initminer→9001 |
| `91000004`  | `proposal_pay_operation`           | proposal 9002 receives 50000 |

## Expected final state

After the mock range has been driven through `process_blocks.sh` and the
two cache refreshes:

- `current_proposals`: 2 rows; **9001 removed=TRUE**, **9002 removed=FALSE, daily_pay=50000**
- `current_proposal_votes`: **1 row** — `(initminer, 9002)` is the only survivor
- `proposal_payments`: 1 row — `(9002, 50000)`
- `proposal_votes_history`: **9 rows** — 5 TRUE inserts + 4 FALSE rows from cascades
- `proposal_vote_stats_cache`: 1 row for 9002, `voters_num = 1`

Two cascade-correctness invariants are checked explicitly by `verify.sql`:

- No active votes on a removed proposal (`proposal_id = 9001` count = 0)
- No active votes from an account that lost voting rights (`steem` count = 0)

## Usage

Three steps, mirroring btracker's mock workflow:

```bash
# 1. Load mock blocks + ops, rewind contexts so the mock range is the
#    next batch the processor will see.
./tests/mocks/install_mock_data.sh --host=localhost --user=haf_admin

# 2. Run the regular block processor against the mock range.
#    stop-at-block matches the highest mock block (91000004).
./scripts/process_blocks.sh --host=localhost --user=hafbe_owner \
                            --stop-at-block=91000004

# 3. Refresh caches and assert the expected post-processing state.
./scripts/verify_mock_data.sh --host=localhost --user=haf_admin
```

### What each step does

**install_mock_data.sh** (loads only — never processes):
1. Loads the four SQL helpers (`types`, `insert_blocks`, `insert_operations`, `update_haf_state`)
2. Inserts mock blocks + ops from `fixtures/`
3. Rewinds both `hafbe_app` and `hafbe_bal` contexts to `(start − 1)` and
   sets `hive_state.consistent_block` to the mock end so the mock range
   becomes the next processable batch

> **Fresh-DB requirement.** This script — like btracker's mock framework — assumes
> the mock range has never been processed against this HAFBE install before.
> Re-running on a DB where the mock blocks were already processed will fail
> with duplicate-key errors on `block_operations` / `sync_time_logs` /
> `current_proposals`. To re-run after a prior run:
> `./scripts/uninstall_app.sh && ./scripts/install_app.sh`, then start the
> three-step workflow again.

**process_blocks.sh** drives the mock range through HAFBE's canonical
main-loop (`hafbe_app.main` → `log_and_process_blocks`), same as a real
sync — including btracker processing and state-provider updates.

**verify_mock_data.sh**:
1. Refreshes `witness_votes_cache` then `proposal_vote_stats_cache` (LIVE
   mode normally refreshes them per-block, but we force a refresh in case
   processing stopped mid-batch)
2. Runs `sql/verify.sql` — prints a PASS/FAIL table and `RAISE EXCEPTION`
   on any failure (`psql -v ON_ERROR_STOP=on` propagates non-zero exit so
   CI fails the job)

### Account-naming rule for fixtures

All accounts referenced by mock op bodies must exist on every realistic
HAF sync. The btracker convention (`blocktrades`, `gtg`, `steem`, `cvk`,
`smooth`, `arhag`, `initminer`, `dan`) covers any sync from block 0+.

**Do NOT** reference accounts created at later hardforks — `hive.fund`,
`steem.dao`, `hiveio` etc. were created at HF17 / HF24 and don't exist
on a partial-sync HAF. Btracker's `get_impacted_balances` runs on every
op body and will hit a NULL-account constraint violation if a referenced
account isn't in `hafd.accounts`. The proposal fixture uses `steem` as
the treasury for that reason.

### Resuming real sync after a mock run

After a mock run the contexts sit at the mock end (`91000004`). To go
back to syncing real blocks, restore the real-data positions:

```sql
-- Find your real head
SELECT MAX(num) AS real_head FROM hafd.blocks WHERE num < 91000000;

-- Restore everything to that head (substitute the real_head value, e.g. 5000000)
UPDATE hafd.hive_state SET consistent_block = 5000000;
UPDATE hafd.contexts
SET current_block_num  = 5000000,
    irreversible_block = 5000000
WHERE name IN ('hafbe_app', 'hafbe_bal');
```

Then `scripts/process_blocks.sh` will resume from the real head.

### Reset (to re-run the mocks)

Reinstall **both** apps. HAFBE and btracker have separate uninstall
scripts — `scripts/uninstall_app.sh` only removes the `hafbe_app`
context, and the leftover `hafbe_bal` context will then desynchronize
with the freshly-installed `hafbe_app`:

```bash
./submodules/btracker/scripts/uninstall_app.sh --host=<haf_host>
./scripts/uninstall_app.sh                     --host=<haf_host>
./scripts/install_app.sh                       --host=<haf_host>
```

`install_app.sh` installs both schemas. Then re-run the three mock
steps.

If you also want to remove the raw mock blocks/ops from HAF itself (e.g.
the mock range is in the way of resuming real sync) the order matters —
`hafd.hive_state.consistent_block` and `hafd.contexts.current_block_num`
FK-reference `hafd.blocks(num)`, so contexts must point AWAY from the
mock range before the blocks can be deleted:

```sql
-- 1. Find the highest real (non-mock) block we have
SELECT MAX(num) AS real_head FROM hafd.blocks WHERE num < 91000000;
-- Note this number; e.g. 5000000

-- 2. Restore hive_state + both contexts to that real head (substitute the real_head value)
UPDATE hafd.hive_state SET consistent_block = 5000000;
UPDATE hafd.contexts
SET current_block_num  = 5000000,
    irreversible_block = 5000000
WHERE name IN ('hafbe_app', 'hafbe_bal');

-- 3. Wipe raw mock ops + blocks from HAF
DELETE FROM hafd.operations
WHERE id >= hafd.operation_id(91000000, 0)
  AND id <  hafd.operation_id(91000010, 0);
DELETE FROM hafd.blocks WHERE num BETWEEN 91000000 AND 91000010;
```

## Adding new scenarios

1. Append ops to `fixtures/proposals/data.json`. Use the next free `op_pos`
   per block, or add another block in `fixtures/blocks/data.json`. Keep
   `block_num >= 91000000`.
2. Add expected-state rows to the `checks(name, expected, actual)` VALUES
   table in `sql/verify.sql`.
3. Re-run the three-step workflow above (install → process_blocks → verify).

The fixture uses `op_name` (e.g. `hive::protocol::create_proposal_operation`)
rather than hardcoded numeric `op_type_id`; the insert function looks up the
id from `hafd.operation_types` at insert time, so fixtures stay portable.

## Troubleshooting

- **`No mock blocks found in hafd.blocks`** — Step 2 (insert blocks) failed
  before Step 4 ran. Check `hafd.blocks` directly: `SELECT num FROM hafd.blocks WHERE num >= 91000000;`

- **PASS table shows FAIL on `daily_pay reflects update`** — likely the
  `update_proposal_operation` body shape doesn't match what HAF emits in
  practice. Check `body_value` of an inserted update op against what real
  HAF data shows.

- **PASS table shows FAIL on `cascade fix` rows** — would mean the
  unified row-by-row processor isn't handling the cascade correctly. The
  whole point of this fixture is to catch that regression.

- **`duplicate key value violates unique constraint "block_operations_op_type_id_block_num"`** (or
  similar collision on `sync_time_logs` / `current_proposals`) during
  `process_blocks.sh` — the mock range was processed against this DB on a
  prior run; the context got rewound but the prior rows are still there.
  This installer is fresh-DB-only (matches btracker). Fix:
  `./scripts/uninstall_app.sh && ./scripts/install_app.sh`, then re-run
  the three mock steps.
