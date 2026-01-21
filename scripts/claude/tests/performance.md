# Performance Tests

## Purpose

Performance tests use JMeter to measure HAFBE API endpoint throughput, response times, and identify performance bottlenecks under load.

## How It Works

1. **Data generation**: Python script creates test data in database
2. **Load testing**: JMeter executes concurrent requests against endpoints
3. **Results collection**: JMeter records timing metrics
4. **Report generation**: HTML dashboard and JUnit XML for CI

## Running Tests

### Full Test Suite
```bash
./tests/performance/run_performance_tests.sh
```

### With Custom Options
```bash
./tests/performance/run_performance_tests.sh \
  --postgresql-host=localhost \
  --postgrest-host=localhost \
  --postgrest-port=3000 \
  --database-size=6000 \
  --test-thread-count=8 \
  --test-loop-count=100
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--postgresql-host=HOST` | PostgreSQL host | localhost |
| `--postgresql-port=PORT` | PostgreSQL port | 5432 |
| `--postgresql-user=USER` | PostgreSQL user | haf_admin |
| `--postgresql-password=PASSWORD` | PostgreSQL password | (empty) |
| `--postgresql-database=NAME` | PostgreSQL database | haf_block_log |
| `--database-size=NUMBER` | Test data size | 1000 |
| `--postgrest-host=HOST` | PostgREST host | localhost |
| `--postgrest-port=PORT` | PostgREST port | 3000 |
| `--test-thread-count=NUMBER` | Concurrent threads | 8 |
| `--test-loop-count=NUMBER` | Iterations per thread | 60 |

## Test File Structure

```
tests/performance/
├── run_performance_tests.sh     # Main test runner
├── generate_db.py               # Test data generator
├── endpoints.jmx                # JMeter test plan
└── result/                      # Output directory
    ├── report.jtl               # Raw JMeter results
    ├── result.xml               # Summary for JUnit conversion
    └── result_report/           # HTML dashboard
        └── index.html           # Main report page
```

## Test Execution Flow

1. **Cleanup**: Remove previous results
2. **Generate data**: `generate_db.py` creates test accounts/witnesses
3. **Run JMeter**: Execute `endpoints.jmx` test plan
4. **Generate report**: JMeter creates HTML dashboard

## JMeter Test Plan

The `endpoints.jmx` file defines:

### Thread Groups
- Configurable thread count (concurrent users)
- Configurable loop count (requests per thread)

### HTTP Samplers
Tests against HAFBE endpoints:
- Account lookups
- Witness queries
- Block searches
- Transaction statistics

### Assertions
- Response code validation
- Response time thresholds

## Interpreting Results

### HTML Dashboard
Located at `tests/performance/result/result_report/index.html`:
- **Summary**: Total requests, error rate, throughput
- **Response Times**: Average, min, max, percentiles
- **Graphs**: Response time over time, throughput

### Key Metrics

| Metric | Description | Target |
|--------|-------------|--------|
| Throughput | Requests/second | Higher is better |
| Avg Response Time | Mean response time | < 500ms |
| Error % | Failed requests | 0% |
| 90th Percentile | Response time at 90% | < 1000ms |

### JMeter Log
Check `jmeter.log` for:
- Error details
- Connection issues
- Configuration problems

## Test Data Generation

The `generate_db.py` script:
- Connects to PostgreSQL directly
- Creates test accounts and witnesses
- Configurable size via `--database-size`

```bash
python3 generate_db.py \
  --host localhost \
  --port 5432 \
  --user haf_admin \
  --database haf_block_log \
  --database-size 6000
```

## Writing New Performance Tests

### Add New Endpoint Test

1. Open `endpoints.jmx` in JMeter GUI:
   ```bash
   jmeter -t tests/performance/endpoints.jmx
   ```

2. Add HTTP Request sampler under Thread Group

3. Configure:
   - Server: `${backend.host}`
   - Port: `${backend.port}`
   - Method: POST
   - Path: `/rpc/endpoint_name`
   - Body: JSON parameters

4. Add assertions (response code, content)

5. Save and test

### Add New Test Data

1. Modify `generate_db.py`:
   - Add function to generate new data type
   - Call from main execution

2. Update `--database-size` handling if needed

## Debugging Performance Issues

### Slow Response Times
1. Check PostgreSQL query plans:
   ```sql
   EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM hafbe_endpoints.get_witness('blocktrades');
   ```

2. Look for sequential scans on large tables

3. Verify indexes exist (check `db/indexes.sql`)

### High Error Rate
1. Check PostgREST logs for errors
2. Verify database connection pool settings
3. Check for statement timeouts

### Connection Refused
1. Ensure PostgREST is running
2. Check port configuration matches test settings

## CI Integration

The `performance-test` job in `.gitlab-ci.yml`:
- Extends `.hafbe_test_base` template
- Runs with 15-minute timeout
- Test parameters: `--database-size=6000 --test-loop-count=1000`
- Compresses results with 7z
- Converts to JUnit XML via `m2u`
- Artifacts:
  - `tests/performance/result/result_report/` - HTML dashboard
  - `tests/performance/results.tar.7z` - Compressed raw data
  - `tests/performance/junit-result.xml` - JUnit report
  - `jmeter.log` - JMeter execution log
