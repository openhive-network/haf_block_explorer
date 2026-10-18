# Regression Tests

## Purpose

Regression tests compare HAFBE's computed account and witness data against expected values from a hived node snapshot. This ensures HAFBE's block processing produces results identical to the reference implementation.

## How It Works

1. **Expected data**: JSON dumps from `hived database_api.list_accounts` and `database_api.list_witnesses`
2. **Load phase**: Python script parses JSON and loads into `hafbe_test.expected_*` tables
3. **Compare phase**: SQL functions compare computed values against expected values
4. **Result**: Any discrepancies are recorded in `hafbe_test.differing_*` tables

## Running Tests

### Full Test Suite
```bash
cd tests/regression
./run_test.sh --host=localhost --type=all
```

### Account Tests Only
```bash
./run_test.sh --host=localhost --type=account
```

### Witness Tests Only
```bash
./run_test.sh --host=localhost --type=witness
```

### Options
| Option | Description | Default |
|--------|-------------|---------|
| `--host=HOSTNAME` | PostgreSQL host | localhost |
| `--port=NUMBER` | PostgreSQL port | 5432 |
| `--user=USERNAME` | PostgreSQL user | haf_admin |
| `--schema=SCHEMA` | HAFBE schema name | hafbe_app |
| `--type=TYPE` | Test type: account, witness, all | all |

## Test File Structure

```
tests/regression/
├── run_test.sh                  # Main test runner
├── install_test_schema.sh       # Installs hafbe_test schema
├── load_expected_data.py        # Python JSON loader
├── accounts_dump.json.gz        # Expected account data fixture
├── witnesses_dump.json.gz       # Expected witness data fixture
└── sql/
    ├── 00_schema.sql            # Test schema definition
    ├── 01_load_expected_data.sql # SQL loading functions
    └── 02_compare.sql           # Comparison functions
```

## Test Schema Tables

### Input Tables (Expected Values)
| Table | Purpose |
|-------|---------|
| `hafbe_test.expected_account_stats` | Expected account data from hived |
| `hafbe_test.expected_witness_props` | Expected witness data from hived |

### Output Tables (Discrepancies)
| Table | Purpose |
|-------|---------|
| `hafbe_test.differing_accounts` | Account IDs with mismatched data |
| `hafbe_test.differing_witnesses` | Witness IDs with mismatched data |
| `hafbe_test.differing_wallet_days` | Days where `wallet_stats_by_day` disagrees with `account_parameters` (stored vs recomputed) |
| `hafbe_test.differing_ops_counts` | Accounts where `account_ops_count` disagrees with the newest `account_op_seq_no + 1` (stored vs recomputed) |

## What Gets Compared

### Account Fields
- `witnesses_voted_for` - Number of witnesses voted for
- `can_vote` - Whether account can vote
- `mined` - Whether account was mined (not created)
- `last_account_recovery` - Timestamp of last recovery
- `created` - Account creation timestamp
- `proxy` - Account's voting proxy
- `recovery_account` - Account's recovery trustee

### Wallet Statistics
`hafbe_test.compare_wallet_stats()` (`--type=wallet`) needs no snapshot: it recomputes
accounts created per day from `account_parameters` and compares it with
`hafbe_app.wallet_stats_by_day`. Run it after sync, after LIVE blocks or after a fork
rollback; it holds at any block.

### Account Operation Counts
`hafbe_test.compare_account_ops_count()` (`--type=opscount`) needs no snapshot either:
it recomputes each account's newest `account_op_seq_no + 1` from
`hafbe_app.account_operations_view` and compares it with `hafbe_app.account_ops_count`.
It holds at any block once massive sync is finalized (the table is filled at that point).

### Witness Fields
- `url` - Witness URL
- `vests` - Total vests voting for witness
- `missed_blocks` - Count of missed blocks
- `last_confirmed_block_num` - Last block produced
- `signing_key` - Witness signing key
- `version` - Witness node version
- `account_creation_fee` - Witness fee preference
- `block_size` - Witness block size preference
- `hbd_interest_rate` - Witness HBD interest rate vote
- `price_feed` - Witness price feed
- `feed_updated_at` - Last price feed update
- `created` - Witness creation timestamp

## Debugging Failures

### Check Discrepancies
```sql
-- View accounts with discrepancies
SELECT * FROM hafbe_test.differing_accounts LIMIT 20;

-- View witnesses with discrepancies
SELECT * FROM hafbe_test.differing_witnesses LIMIT 20;
```

### Compare Single Account
```sql
SELECT * FROM hafbe_test.get_account_comparison(12345);
```
Returns a side-by-side comparison of expected vs computed values.

### Compare Single Witness
```sql
SELECT * FROM hafbe_test.get_witness_comparison(12345);
```

### Common Failure Causes

| Symptom | Likely Cause |
|---------|--------------|
| Many accounts differ | Processing bug in account_parameters |
| Witness vests differ | Vote aggregation issue |
| Timestamps differ | Timezone handling issue |
| New accounts fail | Fixture data outdated |

## Recreating Test Fixtures

### Accounts Fixture

Requires a hived node with increased API limit:

1. Configure hived: `api-limit = 10000000`
2. Sync hived to the target block height
3. Dump data:
   ```bash
   curl -s -o accounts_dump.json \
     --data '{"jsonrpc":"2.0", "method":"database_api.list_accounts", \
              "params": {"start":"", "limit":10000000, "order":"by_name"}, \
              "id":1}' "http://localhost:8091"
   ```
4. Clean apostrophes: `sed -i "s/'//g" accounts_dump.json`
5. Compress: `gzip accounts_dump.json`

### Witnesses Fixture

Similar process using `database_api.list_witnesses` endpoint.

## Adding New Regression Tests

### Add New Comparison Field

1. **Update schema** (`sql/00_schema.sql`):
   - Add column to `expected_*` table
   - Add column to `differing_*` if tracking individual field mismatches

2. **Update loader** (`sql/01_load_expected_data.sql`):
   - Extract new field from JSON in `load_expected_*` function

3. **Update comparison** (`sql/02_compare.sql`):
   - Add field to comparison logic in `compare_*` function
   - Update `get_*_comparison` debug helper

4. **Regenerate fixtures** if testing new data

### Add New Entity Type

1. Create new expected/differing tables in `00_schema.sql`
2. Add loader function in `01_load_expected_data.sql`
3. Add comparison function in `02_compare.sql`
4. Update `run_test.sh` with new test type option
5. Create fixture data JSON file

## CI Integration

The `regression-test` job in `.gitlab-ci.yml`:
- Extends `.hafbe_test_base` template
- Runs against 5M block synced database
- Artifacts: `tests/regression/regression_test.log`
