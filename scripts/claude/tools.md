# Utility Scripts

These scripts help with common development and debugging tasks. **Use them automatically when the task matches their purpose.**

## Available Tools

### Pipeline Log Analyzer

**Location**: `scripts/claude/tools/check-hafbe-pipeline.sh`

**Use when**:
- User asks to analyze a failed CI/CD pipeline
- User asks "why did the pipeline fail?"
- User mentions a pipeline ID or branch with test failures
- Debugging CI job failures

**Usage**:
```bash
# Check latest pipeline on develop
./scripts/claude/tools/check-hafbe-pipeline.sh

# Check specific branch
./scripts/claude/tools/check-hafbe-pipeline.sh feature/my-branch

# Check specific pipeline ID
./scripts/claude/tools/check-hafbe-pipeline.sh 141234
```

**What it does**:
1. Fetches pipeline status from GitLab API
2. Shows summary of all job statuses
3. Lists key jobs (sync, tests, build) with status
4. For failed jobs: extracts relevant error lines from logs
5. Shows running and canceled jobs

**Output includes**:
- Pipeline URL and status
- Job-by-job breakdown
- Extracted error messages from failed jobs
- Test result summary

**Requirements**: `glab` CLI authenticated with GitLab

---

### Sync Test Runner

**Location**: `scripts/claude/tools/run_sync_test.sh`

**Use when**:
- User wants to test sync performance
- User asks to run a sync to a specific block
- Benchmarking block processing speed
- Testing sync changes locally

**Usage**:
```bash
# Sync to 5M blocks (default)
./scripts/claude/tools/run_sync_test.sh

# Sync to specific block
./scripts/claude/tools/run_sync_test.sh 1000000

# Specify host and log file
./scripts/claude/tools/run_sync_test.sh 5000000 172.17.0.2 my_test.log
```

**What it does**:
1. Starts HAFBE sync via `process_blocks.sh`
2. Monitors progress in real-time
3. Automatically stops at target block
4. Reports performance statistics:
   - Total processing time
   - Block ranges processed
   - Average time per block range

**Requirements**: PostgreSQL database with HAF running

---

### Mock Data Installer + Cache Preparer

**Location**: `tests/mocks/install_mock_data.sh` + `scripts/prepare_mock_cache.sh`

**Use when**:
- Testing a feature whose ops only appear past a late launch block (e.g. DHF
  proposals launched at block ~22.3M) and a HAF sync to that point is impractical
- Validating processor + endpoint behaviour end-to-end without waiting for
  real blockchain data
- Reproducing the canonical test fixtures shipped with the repo

**Usage** (after a fresh `install_app.sh`):
```bash
./tests/mocks/install_mock_data.sh --host=localhost --user=haf_admin
./scripts/process_blocks.sh        --host=localhost --stop-at-block=91000006
./scripts/prepare_mock_cache.sh    --host=localhost --user=haf_admin
cd tests/tavern/patterns-mock && pytest get_proposal_votes_history/
```

**What they do**:
- `install_mock_data.sh`: loads fixture blocks/ops at the 91M range, rewinds
  `hafbe_app` and `hafbe_bal` contexts so the mock range becomes the next
  processable batch. Does NOT process the blocks.
- `process_blocks.sh`: drives the mock range through the canonical pipeline.
- `prepare_mock_cache.sh`: refreshes LIVE caches and seeds a deterministic
  `initminer` vests value (setup, not a test). Behavior is asserted through
  the REST API by the Tavern mock suite (`tests/tavern/patterns-mock`).

**Requirements**: Fresh HAFBE+btracker install. Mirrors
`submodules/btracker/tests/mocks/`. Full docs in `tests/mocks/README.md`.

**CI integration**: `docker/docker-compose-mocks.yml` runs the same three-step flow automatically. The `backend-block-processing` service must NOT use `--stop-at-block` — passing `_limit` to `hive.app_next_iteration` prevents the MASSIVE→LIVE mode transition, causing `hive.is_app_in_sync()` to never return TRUE. The `wait-for-haf-be-startup.sh` script supports `--target-block=N` as a debugging utility (checks `current_block_num >= N` directly), but the CI flow uses the default `is_app_in_sync` check.

---

## When to Use These Tools

| User Request | Script to Use |
|-------------|---------------|
| "Check why the pipeline failed" | `check-hafbe-pipeline.sh` |
| "Analyze CI failures" | `check-hafbe-pipeline.sh` |
| "What's wrong with pipeline 12345?" | `check-hafbe-pipeline.sh 12345` |
| "Check the develop pipeline" | `check-hafbe-pipeline.sh develop` |
| "Run sync to 1M blocks" | `run_sync_test.sh 1000000` |
| "Test proposal endpoints without waiting for sync" | `tests/mocks/install_mock_data.sh` → `process_blocks.sh --stop-at-block=91000006` → `prepare_mock_cache.sh` → `pytest tests/tavern/patterns-mock/get_proposal_votes_history/` |
| "Prepare mock cache" | `prepare_mock_cache.sh` |
| "Reproduce CI mock pipeline locally" | `docker compose -f docker/docker-compose-mocks.yml up` (no `--stop-at-block`; wait for `hive.is_app_in_sync`) |
| "Test sync performance" | `run_sync_test.sh` |
| "Benchmark block processing" | `run_sync_test.sh` |

## Error Patterns by Job Type

When analyzing pipeline failures, the script extracts these patterns:

| Job | Error Patterns |
|-----|----------------|
| `sync` | Error, Exception, FATAL, timeout, failed |
| `regression-test` | FAILED, mismatch, differ, AssertionError |
| `performance-test` | Error, Failed, timeout, 0 passed |
| `pattern-test` | FAILED, ERROR, AssertionError, tavern |
| `pattern-test-with-mock-data` | FAILED, ERROR, AssertionError, tavern |
| `sync_with_mock_data` | Timeout, Error, FATAL, failed, is_app_in_sync |
| `python_api_client_test` | FAILED, Error, pytest |
| `lint_*` | violation, L/W/E codes |

## Adding New Tools

When adding new utility scripts:

1. Add the script to `scripts/claude/tools/`
2. Make it executable: `chmod +x scripts/claude/tools/your_script.sh`
3. Document it in this file with:
   - Location
   - Use when (trigger conditions)
   - Usage examples
   - What it does
4. Add to the "When to Use" table

## Expansion Rules

| Change | Action |
|--------|--------|
| New utility script | Add to "Available Tools" section |
| New CI job type | Add error patterns to `check-hafbe-pipeline.sh` |
| New debugging task | Consider creating a helper script |
