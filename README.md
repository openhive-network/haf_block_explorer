# HAF Block Explorer

## Overview

HAF Block Explorer (HAFBE) is a comprehensive blockchain API for querying information about the Hive blockchain. It provides a RESTful API for accessing transactions, operations, accounts, witnesses, and block data.

Built on PostgreSQL and PostgREST, HAFBE processes blockchain data through the Hive Application Framework (HAF) and exposes it via a clean REST API. It integrates three sub-applications to provide complete blockchain data coverage: Balance Tracker (account balances), Reputation Tracker (reputation scores), and HAfAH (account history).

HAFBE is designed for developers building Hive applications, block explorers, analytics tools, and any service that needs access to historical blockchain data.

## Features

- **Block Search**: Query blocks by number, hash, or transaction hash
- **Account Data**: Look up account information, operation history, and statistics
- **Witness Information**: Track witness votes, statistics, and price feeds
- **Transaction Lookup**: Search transactions by hash with full operation details
- **Balance Tracking**: Real-time account balances (HIVE, HBD, VESTS, savings, delegations)
- **Reputation Scores**: Calculated reputation for all accounts
- **Authority History**: Track account key and authority changes over time
- **OpenAPI/Swagger**: Auto-generated API documentation and client generation
- **High Performance**: Optimized PostgreSQL queries and indexes for fast responses

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Hive Blockchain                         │
└─────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                    HAF (Hive Application Framework)             │
│         Receives blocks from hived, stores in PostgreSQL        │
└─────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                      HAF Block Explorer                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │
│  │   btracker  │  │  reptracker │  │         hafah           │ │
│  │  (balances) │  │ (reputation)│  │  (account history)      │ │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘ │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              HAFBE Core Processing                       │   │
│  │   • Witness tracking    • Account statistics            │   │
│  │   • Block search        • Transaction indexing          │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                         PostgREST                               │
│              Converts SQL functions to REST endpoints           │
└─────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                       REST API Clients                          │
│          Applications, Block Explorers, Analytics Tools         │
└─────────────────────────────────────────────────────────────────┘
```

## Tech Stack

- **Database**: PostgreSQL 14 with PL/pgSQL stored procedures
- **API Layer**: PostgREST (automatic REST API from SQL schema)
- **Data Source**: HAF (Hive Application Framework)
- **Languages**: SQL (primary), Bash (scripts), Python 3.12+ (testing/client)
- **Containerization**: Docker, Docker Compose, BuildKit
- **Testing**: Tavern (YAML API tests), pytest, JMeter (performance)
- **Linting**: sqlfluff (SQL), shellcheck (Bash)
- **Package Management**: Poetry (Python dependencies)

## Directory Structure

```
haf_block_explorer/
├── backend/                 SQL application logic
│   ├── endpoint_helpers/    Functions powering API endpoints
│   ├── operation_parsers/   Extract data from blockchain operations
│   └── utilities/           Shared utilities (validation, constants)
├── db/                      Core database layer
│   ├── hafbe_app.sql        Main app setup and processing loop
│   ├── process_*.sql        Block processing functions
│   └── indexes.sql          Database indexes
├── endpoints/               PostgREST API definitions
│   ├── endpoint_schema.sql  All endpoint definitions
│   ├── accounts/            Account endpoints
│   ├── witnesses/           Witness endpoints
│   ├── block-search/        Block search endpoints
│   └── transactions/        Transaction endpoints
├── scripts/                 Operational scripts
│   ├── install_app.sh       Install HAFBE on database
│   ├── process_blocks.sh    Run block processing
│   └── uninstall_app.sh     Remove HAFBE
├── tests/                   Test suites
│   ├── regression/          Compare against hived snapshots
│   ├── tavern/              YAML-based API tests
│   ├── performance/         JMeter performance tests
│   └── functional/          Script tests
├── docker/                  Docker Compose deployment
└── submodules/              Integrated sub-applications
    ├── btracker/            Balance Tracker
    ├── reptracker/          Reputation Tracker
    └── hafah/               HAF Account History (HAfAH)
```

## Prerequisites

Before installing HAF Block Explorer, you need:

1. **HAF Server**: A running HAF (Hive Application Framework) instance with:
   - PostgreSQL 14+
   - HAF SQL extensions installed
   - Block data synced (or syncing)

2. **System Requirements**:
   - PostgreSQL 14 or higher
   - Bash shell
   - Python 3.12+ (for testing and client generation)

3. **For Docker deployment**:
   - Docker Engine 20.10+
   - Docker Compose v2

## Installation

> **Note**: HAFBE uses balance_tracker as a sub-app. If you have balance_tracker installed separately, uninstall it first to avoid schema conflicts.

### Recommended: Using HAF API Node

The easiest way to run HAFBE is using the [HAF API Node](https://gitlab.syncad.com/hive/haf_api_node/) scripts, which manage HAF and all applications together.

### Manual Installation

1. **Clone the repository with submodules**:
   ```bash
   git clone --recursive https://gitlab.syncad.com/hive/haf_block_explorer.git
   cd haf_block_explorer
   ```

2. **Set up dependencies**:
   ```bash
   ./scripts/setup_dependencies.sh --install-all
   ```

3. **Install HAFBE on the database**:
   ```bash
   ./scripts/install_app.sh --host=<db_host> --port=5432 --user=haf_admin
   ```

   Use `./scripts/install_app.sh --help` for all options.

## Quick Start

### Process Blocks

After installation, process blockchain blocks to populate HAFBE data:

```bash
./scripts/process_blocks.sh --host=<db_host>
```

The processing will continue until it catches up with the latest blocks in HAF, then switch to live mode.

Use `./scripts/process_blocks.sh --help` for options including:
- `--stop-at-block=N`: Stop after processing block N
- `--log-file=PATH`: Write logs to file

### Access the API

Once PostgREST is running (default port 3000), access endpoints like:

```bash
# Get account info
curl "http://localhost:3000/rpc/get_account?_account_name=hiveio"

# Search blocks
curl "http://localhost:3000/rpc/get_block?_block_num=1000000"

# Get witness data
curl "http://localhost:3000/rpc/get_witness?_witness_name=blocktrades"
```

### Docker Deployment

```bash
cd docker
docker compose up -d                        # Start all services
docker compose --profile swagger up -d      # Include Swagger UI (port 8080)
docker compose --profile db-tools up -d     # Include PgAdmin/PgHero
```

See [docker/README.md](docker/README.md) for detailed Docker instructions.

## Submodules

HAF Block Explorer integrates three sub-applications:

### Balance Tracker (btracker)

Tracks all account balances in real-time:
- HIVE and HBD liquid balances
- VESTS (staked HIVE)
- Savings balances
- Delegations (incoming and outgoing)
- Recurrent transfers

### Reputation Tracker (reptracker)

Calculates reputation scores for all accounts based on votes received. Reputation is computed using the same algorithm as hived.

### HAfAH - HAF Account History

Provides account history API, including:
- All operations involving an account
- Filtered queries by operation type
- Historical account activity

## Uninstallation

To remove HAFBE and its data from the database:

```bash
./scripts/uninstall_app.sh --host=<db_host>
```

---

## Processing & Synchronization

### Overview

HAFBE processes blockchain data from HAF (Hive Application Framework) via a continuous main loop. The entry point is `hafbe_app.main()` called by `scripts/process_blocks.sh`.

**Processing pipeline:**
1. `scripts/process_blocks.sh` starts the application
2. `hafbe_app.main()` enters an infinite loop calling `hive.app_next_iteration()`
3. For each block range, the system orchestrates:
   - Balance Tracker processing (btracker submodule)
   - HAFBE core processing (5 processors)
   - HAF state provider updates

### Processing Stages

#### MASSIVE_PROCESSING (Bulk Sync)

Used during initial sync or catching up after downtime:
- **Batch size**: 10,000 blocks per iteration
- **Optimization**: `synchronous_commit = OFF` for maximum throughput
- **Behavior**: No cache table updates, indexes created after stage completes

#### LIVE Mode

Used when caught up with blockchain head:
- **Batch size**: 1 block per iteration
- **Optimization**: `synchronous_commit = ON` for data safety
- **Behavior**: Updates cache tables for fast API queries

### Block Processing

Each block range runs through these processors in order:

1. **Account Stats** (`process_account_stats`) - Account creation, recovery, voting rights
2. **Block Operations** (`process_block_operations`) - Operation counts per block
3. **Transaction Stats** (`process_transaction_stats`) - Daily/monthly transaction aggregations
4. **Witness Stats** (`process_witness_stats`) - Witness properties and metadata
5. **Witness Votes** (`process_witness_votes`) - Vote and proxy state management

### Witness Processing

HAFBE tracks comprehensive witness data:
- **Properties**: URL, signing key, price feed, block size preferences
- **Statistics**: Missed blocks, last created block, version
- **Votes**: Current votes, vote history, voter counts
- **Proxies**: Proxy assignments and delegation chains

### Data Flow

```
Hive Blockchain
      │
      ▼
HAF (stores operations in PostgreSQL)
      │
      ▼
process_blocks.sh → hafbe_app.main()
      │
      ├── btracker_process_blocks() → Balance data
      │
      ├── process_account_stats()   → Account parameters
      ├── process_block_operations() → Operation counts
      ├── process_transaction_stats() → Transaction aggregations
      ├── process_witness_stats()   → Witness metadata
      ├── process_witness_votes()   → Vote/proxy state
      │
      └── haf.app_state_providers_update() → HAF core state
```

### Key Processing Functions

| Function | File | Purpose |
|----------|------|---------|
| `process_blocks()` | `db/hafbe_app.sql` | Dispatcher for massive/single processing |
| `process_account_stats()` | `db/process_account_stats.sql` | Account parameters |
| `process_block_operations()` | `db/process_block_operations.sql` | Operation counts |
| `process_transaction_stats()` | `db/process_transaction_stats.sql` | Transaction aggregations |
| `process_witness_stats()` | `db/process_witness_stats.sql` | Witness metadata |
| `process_witness_votes()` | `db/process_witness_votes.sql` | Votes and proxies |

### Stopping Processing

To gracefully stop block processing:

```sql
-- From a separate database session:
SELECT hafbe_app.stopProcessing();
COMMIT;  -- Must commit for the change to be visible
```

The main loop will exit after completing the current block.

---

## API Reference

### Overview

HAFBE exposes a REST API via PostgREST, automatically converting PostgreSQL functions into HTTP endpoints. The API uses JSON for request/response bodies.

### Base URL

```
http://localhost:3000/hafbe-api/
```

When deployed with HAF API Node, the API is typically available at:
```
https://api.hive.blog/hafbe-api/
```

### Authentication

No authentication is required. The API is read-only and publicly accessible.

### Endpoints

#### Block Search Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/block-search` | GET | Search blocks by operation type, account, and time range |

#### Account Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/accounts/{account-name}` | GET | Get account info with balances |
| `/accounts/{account-name}/authority` | GET | Get account keys and authorities |
| `/accounts/{account-name}/operations/comments/{permlink}` | GET | Get operations for a post |
| `/accounts/{account-name}/comments` | GET | List account's posts/comments |
| `/accounts/{account-name}/proxies` | GET | Get accounts proxying to this account |

#### Witness Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/witnesses` | GET | List all witnesses with ranking |
| `/witnesses/{account-name}` | GET | Get single witness info |
| `/witnesses/{account-name}/voters` | GET | List accounts voting for witness |
| `/witnesses/{account-name}/voters/num` | GET | Get voter count for witness |
| `/witnesses/{account-name}/votes-history` | GET | Get witness vote history |

#### Transaction Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/transaction-statistics` | GET | Get aggregated transaction stats per period |
| `/operation-type-statistics` | GET | Get per-op-type operation counts and transaction totals per period |

#### Utility Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/version` | GET | Get HAFBE version (git hash) |
| `/headblock` | GET | Get last synced block number |
| `/operation-type-counts` | GET | Get operation histogram for blocks |
| `/input-type/{input-value}` | GET | Detect input type (block/tx/account) |

### Request/Response Examples

#### Get Account Information

```bash
curl "http://localhost:3000/hafbe-api/accounts/blocktrades"
```

Response:
```json
{
  "id": 440,
  "name": "blocktrades",
  "can_vote": true,
  "reputation": 69,
  "balance": 29594875,
  "vesting_shares": "8172549681941451",
  "witnesses_voted_for": 9,
  "is_witness": true
}
```

#### Search Blocks by Operation Type

```bash
curl "http://localhost:3000/hafbe-api/block-search?operation-types=0&page-size=5"
```

Response:
```json
{
  "total_blocks": 5000000,
  "total_pages": 1000000,
  "blocks_result": [
    {
      "block_num": 5000000,
      "created_at": "2016-09-15T19:47:21",
      "producer_account": "ihashfury",
      "operations": [
        {"op_type_id": 0, "op_count": 2}
      ]
    }
  ]
}
```

#### Get Witness Information

```bash
curl "http://localhost:3000/hafbe-api/witnesses/blocktrades"
```

Response:
```json
{
  "witness_name": "blocktrades",
  "rank": 8,
  "url": "https://blocktrades.us",
  "vests": "82373419958692803",
  "voters_num": 263,
  "price_feed": 0.545,
  "version": "1.27.0",
  "missed_blocks": 935
}
```

#### Get Transaction Statistics

```bash
curl "http://localhost:3000/hafbe-api/transaction-statistics?granularity=monthly"
```

Both statistics endpoints return a **top-level array** with one entry per period, and are not
paginated -- they feed time-series charts, which draw a whole range at once and need every
period of the requested range.

Response:
```json
[
  {
    "date": "2024-01-01T00:00:00",
    "trx_count": 15234567,
    "avg_trx": 12,
    "min_trx": 0,
    "max_trx": 156,
    "last_block_num": 81748629
  }
]
```

`/operation-type-statistics` returns the same flat array, with each entry carrying a per-op-type
breakdown under `operations[]`.

Because that per-op-type breakdown makes each entry much larger, `/operation-type-statistics`
defaults to the **most recent 1 year** when called at `granularity=daily` with no `from-block`
(an unbounded daily histogram is ~3,750 periods / ~6.6 MB). An explicitly supplied `from-block`
is always honoured in full, at every granularity, and `monthly`/`yearly` are never defaulted.
`/transaction-statistics` is never bounded -- one row per period keeps a full-history daily
response around 400 kB.

### Common Parameters

Many endpoints support these standard parameters. Note that `page` / `page-size` are **rejected**
by the two statistics endpoints above -- they are not part of those function signatures, so
PostgREST answers `404 PGRST202` ("Could not find the function ... in the schema cache") rather
than ignoring them. Those endpoints return every period in the range as a flat array.

| Parameter | Type | Description |
|-----------|------|-------------|
| `page` | integer | Page number (1-indexed) -- rejected by the statistics endpoints |
| `page-size` | integer | Results per page (default: 100, max: 1000) -- rejected by the statistics endpoints |
| `direction` | string | Sort order: `asc` or `desc` |
| `from-block` | string | Block number or timestamp (YYYY-MM-DD HH:MI:SS) |
| `to-block` | string | Block number or timestamp (YYYY-MM-DD HH:MI:SS) |

### OpenAPI/Swagger

The complete OpenAPI 3.1 specification is auto-generated from SQL comments.

**Access the spec:**
```bash
curl "http://localhost:3000/hafbe-api/"
```

**Swagger UI:** Available at port 8080 when deployed with Docker using:
```bash
docker compose --profile swagger up -d
```

### Error Responses

| Status | Description |
|--------|-------------|
| 200 | Success |
| 404 | Resource not found (e.g., account doesn't exist) |
| 400 | Invalid parameters |

---

## Testing

### Overview

HAFBE uses a multi-layered testing strategy to ensure API correctness, data integrity, and performance:

| Test Type | Purpose |
|-----------|---------|
| **Regression** | Compare computed data against hived snapshots |
| **Tavern** | Validate API response patterns (YAML-based) |
| **Performance** | JMeter load testing for throughput measurement |
| **Functional** | Verify install/uninstall scripts work correctly |

### Quick Test Commands

```bash
# Regression tests - compare against hived snapshots
cd tests/regression && ./run_test.sh --host=localhost --type=all

# Tavern API pattern tests (parallel execution)
cd tests/tavern/patterns-mainnet && pytest -n 8 .

# Performance tests with JMeter
./tests/performance/run_performance_tests.sh --postgrest-host=localhost

# Functional script tests
./tests/functional/test_scripts.sh --host=localhost
```

### Test Types

#### Regression Tests
Compare HAFBE's computed account and witness data against expected values from hived node snapshots. Detects calculation errors and processing bugs.

- **Location**: `tests/regression/`
- **Runner**: `./run_test.sh --host=localhost --type=all`
- **Options**: `--type=account`, `--type=witness`, `--type=all`

#### Tavern API Tests
YAML-based API tests using pytest-tavern. Validates endpoint responses against saved pattern files.

- **Location**: `tests/tavern/patterns-mainnet/`
- **Runner**: `pytest -n 8 .`
- **Environment**: Requires `HAFBE_ADDRESS` and `HAFBE_PORT`

#### Performance Tests
JMeter-based load testing to measure endpoint throughput and response times.

- **Location**: `tests/performance/`
- **Runner**: `./run_performance_tests.sh`
- **Output**: HTML dashboard at `result/result_report/index.html`

#### Functional Tests
Verifies install and uninstall scripts work correctly.

- **Location**: `tests/functional/`
- **Runner**: `./test_scripts.sh --host=localhost`

### CI/CD Integration

Tests run automatically in the GitLab CI pipeline:

```
detect → lint → build → sync → test → publish
```

| CI Job | Test Type | Artifacts |
|--------|-----------|-----------|
| `regression-test` | Regression | `regression_test.log` |
| `pattern-test` | Tavern | JUnit XML report |
| `performance-test` | Performance | HTML report |
| `setup-scripts-test` | Functional | - |

### Writing New Tests

1. **Regression**: Add comparison logic to `tests/regression/sql/02_compare.sql`
2. **Tavern**: Create `.tavern.yaml` file in appropriate `tests/tavern/patterns-mainnet/` directory
3. **Performance**: Modify `tests/performance/endpoints.jmx` JMeter test plan
4. **Functional**: Add tests to `tests/functional/test_scripts.sh`

For detailed test documentation, see `scripts/claude/tests.md`.

---

## Contributing

Contributions are welcome! Please follow these guidelines:

1. **Fork the repository** and create a feature branch
2. **Follow coding conventions**:
   - SQL: Max 170 char lines, use `SET ROLE hafbe_owner;`
   - Bash: Use `set -euo pipefail`, include `--help` option
   - Python: Python 3.12+, use Poetry for dependencies
3. **Add tests** for new functionality
4. **Update documentation** in `scripts/claude/` for significant changes
5. **Submit a merge request** with clear description

### Development Workflow

```bash
# Clone with submodules
git clone --recursive https://gitlab.syncad.com/hive/haf_block_explorer.git

# Make changes to SQL files
vim backend/endpoint_helpers/your_function.sql

# Install changes
./scripts/install_app.sh --host=localhost

# Run tests
cd tests/tavern/patterns-mainnet && pytest -n 8 .
```

---

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

---

## Links

- **Repository**: [GitLab - haf_block_explorer](https://gitlab.syncad.com/hive/haf_block_explorer)
- **HAF Documentation**: [GitLab - HAF](https://gitlab.syncad.com/hive/haf)
- **HAF API Node**: [GitLab - haf_api_node](https://gitlab.syncad.com/hive/haf_api_node)
- **Hive Developer Portal**: [developers.hive.io](https://developers.hive.io)
- **Issue Tracker**: [GitLab Issues](https://gitlab.syncad.com/hive/haf_block_explorer/-/issues)
