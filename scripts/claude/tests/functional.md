# Functional Tests

## Purpose

Functional tests verify that HAFBE's install and uninstall scripts work correctly. This ensures deployment scripts don't break between releases.

## How It Works

1. **Reinstall test**: Runs `install_app.sh` on existing database
2. **Uninstall test**: Runs `uninstall_app.sh` to remove schema
3. **Validation**: Scripts exit with non-zero status on failure

## Running Tests

### Basic Execution
```bash
cd tests/functional
./test_scripts.sh --host=localhost
```

### Options
| Option | Description | Default |
|--------|-------------|---------|
| `--host=HOSTNAME` | PostgreSQL host | localhost |

## Test File Structure

```
tests/functional/
└── test_scripts.sh              # Main test runner
```

## What Gets Tested

### Test 1: Reinstall App
```bash
./install_app.sh --host=$POSTGRES_HOST
```
- Verifies schema can be reinstalled over existing installation
- Tests idempotency of install script

### Test 2: Uninstall App
```bash
./uninstall_app.sh --host=$POSTGRES_HOST
```
- Verifies schema removal works correctly
- Tests cleanup of all HAFBE objects

## Prerequisites

Tests require:
1. HAFBE schema already installed and synced to 5M blocks
2. PostgreSQL accessible at specified host
3. Submodules initialized (hafah, btracker, reptracker)

## Adding New Functional Tests

### Add Test to Existing Script

Edit `test_scripts.sh`:
```bash
echo "Test N. Description..."
./scripts/your_script.sh --host="$POSTGRES_HOST"
echo "Test completed successfully"
```

### Test New Script

1. Add test block to `test_scripts.sh`
2. Include descriptive echo statements
3. Rely on script's own exit codes for pass/fail
4. Keep test order logical (install before uninstall)

## Debugging Failures

### Check Script Output
Tests use `set -euo pipefail`, so first failing command stops execution. Look for:
- SQL errors in output
- Permission denied errors
- Missing dependencies

### Common Failure Causes

| Symptom | Cause | Solution |
|---------|-------|----------|
| Permission denied | Wrong PostgreSQL user | Use haf_admin user |
| Schema not found | HAFBE not installed | Install HAFBE first |
| Submodule error | Missing submodules | `git submodule update --init` |

### Manual Testing
Run individual scripts manually with verbose output:
```bash
./scripts/install_app.sh --host=localhost 2>&1 | tee install.log
./scripts/uninstall_app.sh --host=localhost 2>&1 | tee uninstall.log
```

## CI Integration

The `setup-scripts-test` job in `.gitlab-ci.yml`:
- Extends `.hafbe_test_base` template
- Initializes submodules before running tests
- Creates necessary directories for hafah setup
- Runs against synced 5M block database
