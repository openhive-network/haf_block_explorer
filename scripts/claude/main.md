# HAF Block Explorer - Architecture & Development Guide

## Overview

HAF Block Explorer (HAFBE) is a blockchain API that processes and serves Hive blockchain data. It's built as a **HAF application** - meaning it uses the Hive Application Framework to subscribe to blockchain operations and maintain synchronized state in PostgreSQL.

**How data flows:**
1. HAF receives blockchain data from hived and stores it in PostgreSQL
2. HAFBE processes blocks via `process_blocks.sh`, extracting relevant operations
3. Data is stored in HAFBE's schema tables
4. PostgREST exposes SQL functions as REST endpoints

## Directory Structure

```
backend/                 SQL backend logic
├── endpoint_helpers/    Functions that power API endpoints
├── operation_parsers/   Extract data from blockchain operations
└── utilities/           Shared SQL utilities (validation, constants)

db/                      Core database layer
├── hafbe_app.sql        Main app setup, context creation, main loop
├── process_*.sql        Block processing functions
├── builtin_roles.sql    Database roles setup
└── indexes.sql          Table indexes

endpoints/               PostgREST API definitions
├── endpoint_schema.sql  Main endpoint definitions
├── accounts/            Account-related endpoints
├── witnesses/           Witness-related endpoints
├── block-search/        Block search endpoints
├── transactions/        Transaction endpoints
└── types/               SQL type definitions

scripts/                 Operational scripts
├── install_app.sh       Install HAFBE on database
├── process_blocks.sh    Run block processing loop
├── uninstall_app.sh     Remove HAFBE from database
└── ci-helpers/          CI/CD helper scripts

tests/                   Test suites
├── regression/          Compare against hived snapshots
├── tavern/              YAML-based API tests
├── performance/         JMeter performance tests
└── functional/          Script functionality tests

submodules/              Integrated sub-applications
├── btracker/            Balance tracking
├── reptracker/          Reputation tracking
└── hafah/               HAF Account History (HAfAH)
```

## Schema Conventions

HAFBE uses these PostgreSQL schema prefixes:

| Schema | Purpose |
|--------|---------|
| `hafbe_app` | Core app tables and processing functions |
| `hafbe_endpoints` | PostgREST-exposed API functions |
| `hafbe_views` | Views for data access |
| `hafbe_bal` | Balance data (from btracker) |
| `reptracker_app` | Reputation data (from reptracker) |

**Role pattern**: Always `SET ROLE hafbe_owner;` at the start of schema files.

**Processing stages**:
- `MASSIVE_PROCESSING`: Bulk sync mode (large block ranges)
- `live`: Real-time processing (block-by-block)

## Development Workflow

### Making SQL Changes

1. **Identify the right file**:
   - Processing logic → `db/process_*.sql`
   - Endpoint helpers → `backend/endpoint_helpers/`
   - Utilities → `backend/utilities/`
   - API endpoints → `endpoints/`

2. **Apply changes**:
   ```bash
   ./scripts/install_app.sh --host=<db_host>
   ```

3. **Test locally**:
   ```bash
   # Tavern API tests
   cd tests/tavern/patterns-mainnet && pytest

   # Regression tests
   cd tests/regression && ./run_test.sh --host=localhost
   ```

### Key Scripts

| Script | Purpose | When to use |
|--------|---------|-------------|
| `scripts/install_app.sh` | Install/update schema | After SQL changes |
| `scripts/process_blocks.sh` | Process blockchain blocks | To sync data |
| `scripts/uninstall_app.sh` | Remove app from DB | Clean reinstall |

## Key Files Reference

| File | Purpose |
|------|---------|
| `db/hafbe_app.sql` | App initialization, HAF context, main loop |
| `db/process_witness_stats.sql` | Witness statistics processing |
| `db/process_witness_votes.sql` | Witness vote tracking |
| `db/process_account_stats.sql` | Account statistics |
| `endpoints/endpoint_schema.sql` | All PostgREST endpoint definitions |
| `backend/utilities/blocksearch.sql` | Block search utilities |
| `.gitlab-ci.yml` | CI/CD pipeline configuration |

## HAF Integration

### What is HAF?

HAF (Hive Application Framework) is the data layer that:
- Connects to hived and receives blockchain data
- Stores all operations in PostgreSQL
- Provides app registration and state management
- Handles block reversibility (forks)

### Key HAF Concepts

**Context**: An app's subscription to blockchain data. Created with:
```sql
SELECT haf.app_create_context('hafbe_app', 'hafbe_owner');
```

**App State**: HAF tracks which block each app has processed. Query with:
```sql
SELECT * FROM haf.contexts WHERE name = 'hafbe_app';
```

**Main Loop Pattern**: Apps process blocks in a loop:
```sql
-- Get next block range
SELECT * FROM haf.app_next_iteration(_context);
-- Process blocks
CALL process_blocks(_first_block, _last_block);
-- Mark complete
PERFORM haf.app_context_set_current_block_num(_context, _last_block);
```

### When You Need HAF Internals

HAF is NOT a submodule - it's installed separately on the database server.

**If you need to understand HAF functions or behavior:**
1. ASK THE USER where their HAF repository is cloned
2. Read `<haf_path>/scripts/claude/main.md` for HAF architecture
3. Key HAF SQL is in `<haf_path>/src/hive_fork_manager/`

**Common HAF functions used by HAFBE:**
- `haf.app_create_context()` - Register app
- `haf.app_next_iteration()` - Get next blocks to process
- `haf.app_context_set_current_block_num()` - Mark progress
- `haf.get_impacted_accounts()` - Get accounts in an operation

## Submodule Integration

HAFBE integrates three sub-applications that extend its functionality:

### Balance Tracker (btracker)
- **Purpose**: Tracks account balances (HIVE, HBD, VESTS, savings, delegations)
- **Schema**: `hafbe_bal`
- **Docs**: `submodules/btracker/scripts/claude/`

### Reputation Tracker (reptracker)
- **Purpose**: Calculates account reputation scores from votes
- **Schema**: `reptracker_app`
- **Docs**: `submodules/reptracker/scripts/claude/`

### HAfAH - HAF Account History
- **Purpose**: Provides account history API
- **Docs**: `submodules/hafah/CLAUDE.md` (basic documentation only - no modular docs)

### Working with Submodules

**NEVER duplicate submodule documentation** - always reference their docs.

When making changes that span HAFBE and submodules:
1. Make submodule changes in their respective repos
2. Update submodule commit in HAFBE: `git submodule update --remote <submodule>`
3. Test integration via HAFBE's CI pipeline

## Coding Conventions

### SQL
- Max line length: 170 characters (per `.sqlfluff`)
- Use `SET ROLE hafbe_owner;` at schema file start
- Prefix functions with schema name
- Use `RETURNS TABLE` for result sets

### Bash
- Use `set -euo pipefail`
- Options format: `--option=value`
- Include `print_help()` function in scripts

### Python (tests)
- Python 3.12+ required
- Use Poetry for dependencies
- pytest for test execution

## Expansion Rules

When modifying this documentation:

| Change Type | Action |
|-------------|--------|
| New submodule | Add to "Submodule Integration" section |
| Architecture change | Update relevant section in this file |
| New schema | Add to "Schema Conventions" table |
| New key file | Add to "Key Files Reference" table |

For changes to other areas, update the appropriate doc file:
- Processing: `scripts/claude/processing.md`
- Endpoints: `scripts/claude/endpoints.md`
- Tests: `scripts/claude/tests.md`
- Tools: `scripts/claude/tools.md`
