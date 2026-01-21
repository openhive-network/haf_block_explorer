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

## When to Use These Tools

| User Request | Script to Use |
|-------------|---------------|
| "Check why the pipeline failed" | `check-hafbe-pipeline.sh` |
| "Analyze CI failures" | `check-hafbe-pipeline.sh` |
| "What's wrong with pipeline 12345?" | `check-hafbe-pipeline.sh 12345` |
| "Check the develop pipeline" | `check-hafbe-pipeline.sh develop` |
| "Run sync to 1M blocks" | `run_sync_test.sh 1000000` |
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
