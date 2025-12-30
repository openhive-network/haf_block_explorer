# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

HAF Block Explorer is a PostgreSQL-based REST API for querying Hive blockchain data. It provides transaction/operation search by account, block number, block hash, or transaction hash, plus witness (block producer) information. Built as a HAF (Hive Application Framework) sub-application using PostgREST to automatically expose PostgreSQL functions as REST endpoints.

**Stack:** PostgreSQL/PL/pgSQL, PostgREST, Python (testing), Bash (CLI), Docker

## Common Commands

```bash
# Setup dependencies (git submodules)
./scripts/setup_dependencies.sh --install-all

# Install app on HAF database
./scripts/install_app.sh [--only-hafbe|--only-apps] [--blocksearch-indexes=true/false]

# Process blocks from HAF
./scripts/process_blocks.sh

# Start PostgREST API server (port 3000)
./scripts/start_postgrest.sh

# Uninstall
./scripts/uninstall_app.sh

# Run performance tests (requires virtual env)
source .tests/bin/activate
./tests/run_performance_tests.sh --help
deactivate

# Docker quickstart (5M blocks demo)
curl https://gtg.openhive.network/get/blockchain/block_log.5M -o docker/blockchain/block_log
cd docker && docker compose up -d
```

## Architecture

### Three-Layer PostgreSQL Schema

1. **`hafbe_backend`** - Business logic, data processing, role-based access control
2. **`hafbe_app`** - HAF-managed application state, block processing stages
3. **`hafbe_endpoints`** - REST API functions exposed via PostgREST

**Data Flow:** `HAF (hive.*)` → `hafbe_app` → `hafbe_backend` → `hafbe_endpoints`

### PostgREST Integration

- Config: `postgrest.conf` - exposes only `hafbe_endpoints` schema on port 3000
- Functions named `get_*` become HTTP GET endpoints: `hafbe_endpoints.get_account(name)` → `GET /hafbe-api/accounts/{name}`
- OpenAPI spec embedded in SQL via `hafbe_endpoints.root()` function
- Extra search path includes `hafbe_bal` (balance tracker) and `reptracker_app` (reputation tracker)

### Bundled Sub-Applications

- **Balance Tracker** (`hafbe_bal` schema) - HIVE/HBD balance queries
- **HAfAH** - HAF API Helper
- **Reputation Tracker** (`reptracker_app` schema) - Account reputation data

Located in `submodules/` - share the same database.

### Block Processing Pipeline

1. HAF syncs blockchain to `hive.*` tables
2. `hafbe_app` processes via stages: MASSIVE_PROCESSING (10000 blocks at a time) → LIVE_STAGE (real-time)
3. Processing updates account stats, witness votes, operation counts
4. `hafbe_endpoints` queries processed data

## Directory Structure

- `backend/` - Core business logic (SQL), types, utilities
- `database/` - Schema definitions, indexes, processing logic
- `endpoints/` - REST API endpoint definitions (SQL) organized by category: accounts, block-search, transactions, witnesses
- `scripts/` - CLI scripts for setup, processing, CI helpers
- `tests/tavern/` - Tavern YAML-based API tests
- `docker/` - Docker Compose setup with profiles (swagger, db-tools)
- `submodules/` - Git submodules (haf, btracker, hafah, reptracker)

## Code Standards

**SQL Linting:** SQLFluff with PostgreSQL dialect (`.sqlfluff`), max line length 170

**Bash:** All scripts use strict mode (`set -euo pipefail`)

**Adding an endpoint:** Create SQL function in `endpoints/{category}/`, embed OpenAPI spec in SQL comments

## CI Pipeline

Main stages: lint → build → sync → test → publish → cleanup

**Quick Test Mode** (for SQL/test-only changes, ~5 min vs ~60 min):
```
QUICK_TEST=true
QUICK_TEST_HAF_COMMIT=<sha-from-cache>
```
Find cache keys: `ssh hive-builder-10 'ls -lt /nfs/ci-cache/haf/*.tar | head -5'`
