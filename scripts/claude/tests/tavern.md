# Tavern API Tests

## Purpose

Tavern tests validate HAFBE API endpoint responses against expected patterns. They use pytest-tavern, a YAML-based API testing framework that:
- Validates response structure and status codes
- Compares responses against saved pattern files
- Supports both positive (success) and negative (error) test cases

## How It Works

1. **Test definition**: YAML files describe HTTP requests and expected responses
2. **Pattern matching**: Responses are compared against `.out.json` pattern files
3. **Validation**: Custom `validate_response` function from `tests_api` handles comparison
4. **Parallel execution**: pytest-xdist runs tests in parallel for speed

## Running Tests

### Run All Tests (Parallel)
```bash
export HAFBE_ADDRESS=localhost
export HAFBE_PORT=3000
cd tests/tavern/patterns-mainnet
pytest -n 8 .
```

### Run Specific Endpoint Tests
```bash
pytest -n 8 get_witness/
pytest -n 8 get_witnesses/positive/
```

### Run Single Test
```bash
pytest get_witness/blocktrades.tavern.yaml
```

### Generate JUnit Report
```bash
pytest -n 8 --junitxml report.xml .
```

### Verbose Output
```bash
pytest -v get_witness/blocktrades.tavern.yaml
```

## Test File Structure

```
tests/tavern/
├── common.yaml                      # Shared configuration
├── pytest.ini                       # pytest markers
└── patterns-mainnet/                # Test cases
    ├── get_account/                 # Account endpoint tests
    │   ├── blocktrades.tavern.yaml
    │   └── non_existent_witness.tavern.yaml
    ├── get_witnesses/               # Witnesses list endpoint
    │   ├── positive/                # Success cases
    │   │   ├── first_page.tavern.yaml
    │   │   └── order_by_rank.tavern.yaml
    │   └── negative/                # Error cases
    │       ├── exceeds_page_size.tavern.yaml
    │       └── negative_page_num.tavern.yaml
    └── ...                          # Other endpoints
```

## YAML Test Structure

### Basic Positive Test
```yaml
---
test_name: Hafbe PostgREST

marks:
  - patterntest

includes:
  - !include ../../common.yaml

stages:
  - name: test
    request:
      url: "{service.proto:s}://{service.server:s}:{service.port}/rpc/get_witness"
      method: POST
      headers:
        content-type: application/json
        accept: application/json
      json:
        account-name: "blocktrades"
    response:
      status_code: 200
      verify_response_with:
        function: validate_response:compare_rest_response_with_pattern
        extra_kwargs:
          ignore_tags: "<hafbe cache_update>"
```

### Negative Test (Error Case)
```yaml
---
test_name: Hafbe PostgREST

marks:
  - patterntest
  - negative

includes:
  - !include ../../../common.yaml

stages:
  - name: test
    request:
      url: "{service.proto:s}://{service.server:s}:{service.port}/rpc/get_witnesses"
      method: POST
      headers:
        content-type: application/json
        accept: application/json
      json:
        page-size: 1001
    response:
      status_code: 400
      verify_response_with:
        function: validate_response:compare_rest_response_with_pattern
        extra_kwargs:
          error_response: true
```

## Configuration

### common.yaml
Defines shared variables for all tests:
```yaml
---
name: Common test values
description: Common values for tests

variables:
  service:
    proto: http
    server: "{tavern.env_vars.HAFBE_ADDRESS}"
    port: "{tavern.env_vars.HAFBE_PORT}"
```

### pytest.ini
Defines test markers:
```ini
[pytest]
markers =
    patterntest: Mark tests using patterns to compare results
    negative: Mark error tests
```

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `HAFBE_ADDRESS` | Yes | PostgREST host (e.g., localhost) |
| `HAFBE_PORT` | Yes | PostgREST port (e.g., 3000) |

## Pattern Files

Tavern tests use pattern matching via the `validate_response` module from `tests_api`. Each test automatically generates/compares against a `.out.json` file.

### Pattern File Location
Pattern files are named after the test file:
- Test: `get_witness/blocktrades.tavern.yaml`
- Pattern: `get_witness/blocktrades.out.json`

### Updating Patterns
When endpoint response structure changes:
1. Delete the old `.out.json` file
2. Run the test - it will fail but generate new pattern
3. Review the new pattern file
4. Commit both test and pattern files

## Writing New Tests

### Add Test for Existing Endpoint

1. Create YAML file in appropriate directory:
   - `positive/` for success cases
   - `negative/` for error cases

2. Follow naming convention: `<description>.tavern.yaml`

3. Use the standard template (see examples above)

4. Run test to generate pattern file:
   ```bash
   pytest -v your_test.tavern.yaml
   ```

5. Review and commit both files

### Add Tests for New Endpoint

1. Create endpoint directory: `patterns-mainnet/<endpoint_name>/`

2. Create positive tests: `positive/` subdirectory

3. Create negative tests: `negative/` subdirectory

4. Common test cases to include:
   - Default parameters
   - Pagination (first page, last page)
   - Sorting options
   - Invalid parameters (negative numbers, exceeds limits)
   - Non-existent resources

## Debugging Failures

### View Actual Response
When a test fails, the actual response is saved as `*.out.json`:
```bash
cat get_witness/blocktrades.out.json
```

### Common Failure Causes

| Symptom | Cause | Solution |
|---------|-------|----------|
| Status 500 | SQL exception | Check PostgREST/PostgreSQL logs |
| Pattern mismatch | Response structure changed | Update pattern file |
| Connection refused | PostgREST not running | Start PostgREST service |
| Timeout | Slow query | Check database performance |

### CI Artifacts
On CI failure, download:
- `docker/container-logs.txt` - Service logs
- `*.out.json` files - Actual responses
- JUnit XML report - Test summary

## CI Integration

The `pattern-test` job in `.gitlab-ci.yml`:
- Extends `.test-with-docker-compose-tavern` template
- Clones `tests_api` for validation functions
- Warms up database with complex query before tests
- Runs with 8 parallel workers
- Artifacts: JUnit XML, container logs, `*.out.json` files
