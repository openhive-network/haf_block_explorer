# HAF Block Explorer

## Project Overview

HAF Block Explorer is a blockchain API for querying Hive blockchain data including transactions, operations, accounts, and witnesses. Built on PostgreSQL/PostgREST, it provides a RESTful API for searching by account name, block number, block hash, or transaction hash.

Key features:
- Integrated Balance Tracker, Reputation Tracker, and HAfAH (Account Authority History) as submodules
- Block processing and synchronization from HAF (Hive Application Framework)
- Witness vote tracking, statistics, and price feed data
- OpenAPI/Swagger documentation with automatic client generation

## Tech Stack

- **Database**: PostgreSQL 14 with PL/pgSQL stored procedures
- **API Layer**: PostgREST (REST API from SQL schema)
- **Languages**: SQL (primary), Bash (scripts), Python 3.12+ (testing/client)
- **Containerization**: Docker, Docker Compose, BuildKit
- **Testing**: Tavern (YAML-based API tests), pytest, JMeter (performance)
- **Linting**: sqlfluff (SQL), shellcheck (Bash)
- **Package Management**: Poetry (Python)

## Directory Structure

```
backend/           SQL application layer (roles, processing)
database/          Core schema, main loop, block processing
endpoints/         REST API endpoint definitions (OpenAPI)
scripts/           Operational scripts (install, process, start)
  ci-helpers/      CI/CD helper scripts
  python_api_package/  Python API client generation
tests/
  regression/      Regression tests (account/witness comparison vs hived)
  tavern/          YAML-based API pattern tests
    patterns-mainnet/  Tests against synced mainnet data
  performance/     JMeter performance tests
  functional/      Script functionality tests
docker/            Docker Compose deployment
submodules/
  btracker/        Balance Tracker
  hafah/           Account Authority History
  reptracker/      Reputation Tracker
```

## Development Commands

### Setup
```bash
./scripts/setup_dependencies.sh --install-all   # Install dependencies
./scripts/install_app.sh                         # Install DB schema
```

### Run
```bash
./scripts/process_blocks.sh    # Process/sync blocks
./scripts/start_postgrest.sh   # Start API server (port 3000)
```

### Test
```bash
# Regression tests (account/witness comparison)
cd tests/regression && ./run_test.sh --host=localhost --type=all

# Tavern API tests
cd tests/tavern/patterns-mainnet && pytest -n 8 --junitxml report.xml .

# Performance tests
./tests/run_performance_tests.sh

# Functional tests
./tests/functional/test_scripts.sh --host=localhost

# Python client tests
cd scripts/python_api_package && pytest tests/
```

### Docker
```bash
cd docker
docker compose up -d                        # Start all services
docker compose --profile swagger up         # Include Swagger UI (port 8080)
docker compose --profile db-tools up        # Include PgAdmin/PgHero
docker compose down -v                      # Stop and remove volumes
```

## Key Files

| File | Purpose |
|------|---------|
| `.gitlab-ci.yml` | CI/CD pipeline (lint, build, sync, test, publish) |
| `postgrest.conf` | PostgREST configuration (schema: hafbe_endpoints) |
| `docker-bake.hcl` | Docker BuildKit configuration |
| `database/database_schema.sql` | Core tables and schema |
| `database/main_loop.sql` | Primary sync loop |
| `endpoints/endpoint_schema.sql` | API endpoint definitions |
| `.sqlfluff` | SQL linting config (PostgreSQL, max 170 chars) |

## Coding Conventions

### SQL
- Schema prefixes: `hafbe_app`, `hafbe_endpoints`, `hafbe_bal`, `reptracker_app`
- Role pattern: `SET ROLE hafbe_owner` at schema start
- Max line length: 170 characters
- Processing stages: MASSIVE_PROCESSING (bulk sync), live (real-time)

### Bash
- Use `set -euo pipefail`
- Options format: `--option=value`
- Include `print_help()` function

### Python
- Python 3.12+ required
- Poetry for dependencies
- pytest for testing

## CI/CD Notes

### Pipeline Stages
1. **lint**: shellcheck (Bash), sqlfluff (SQL)
2. **build**: HAF image, Docker images, Python client
3. **sync**: Docker Compose test environment setup
4. **test**: regression, performance, pattern (Tavern), Python client
5. **publish**: Docker images, Python packages, WAX specs
6. **cleanup**: Manual cache cleanup

### Cache Architecture
- Local: `/cache/replay_data_haf_<commit>/` (per builder)
- NFS shared: `/nfs/ci-cache/haf_sync/<commit>/` (cross-builder)
- Runner tags: `data-cache-storage` (NFS), `fast` (fast builders)

### Key Variables
- `HAF_COMMIT`: Pinned HAF commit for consistency
- `BLOCK_LOG_SOURCE_DIR`: Block log location
- Test data: 5M blocks prepared via `prepare_haf_data` job

### HAF Version
HAF is pinned via `HAF_COMMIT` variable in `.gitlab-ci.yml` (not a submodule).
Docker images are pulled from registry using this commit.

### Submodule Commits
App submodules (btracker, hafah, reptracker) are pinned to specific commits:
```bash
git submodule update --init --recursive
```
