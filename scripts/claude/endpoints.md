# HAFBE API Endpoints

This document covers the REST API endpoints exposed by HAF Block Explorer via PostgREST.

## Overview

HAFBE uses PostgREST to automatically expose PostgreSQL functions as REST endpoints. Each SQL function in the `hafbe_endpoints` schema becomes a callable REST endpoint.

**API Pattern:**
```
POST /rpc/<function_name>       # RPC-style call
GET  /<path-defined-in-openapi> # RESTful route (via rewrite rules)
```

**Base URL:** `/hafbe-api` (configured in PostgREST)

## OpenAPI Specification

HAFBE auto-generates an OpenAPI 3.1 specification from SQL comments.

**Access the spec:**
- `GET /hafbe-api/` returns the full OpenAPI JSON
- Swagger UI available at port 8080 when deployed with `--profile swagger`

**Annotation format in SQL:**
```sql
/** openapi:paths
/accounts/{account-name}:
  get:
    tags:
      - Accounts
    summary: Get account information
    operationId: hafbe_endpoints.get_account
    ...
*/
```

**Code generation markers:**
```sql
-- openapi-generated-code-begin
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_account(...)
-- openapi-generated-code-end
```

## Endpoint Categories

| Category | Tag | Description |
|----------|-----|-------------|
| Block Search | `Block-search` | Query blocks by operations, filters, time ranges |
| Accounts | `Accounts` | Account info, balances, authorities, operations |
| Witnesses | `Witnesses` | Witness data, votes, rankings |
| Proposals | `Proposals` | Proposal vote history |
| Transactions | `Transactions` | Transaction statistics and aggregations |
| Other | `Other` | API metadata, input type detection |

## Endpoints Inventory

### Block Search Endpoints

| Endpoint | Function | Description |
|----------|----------|-------------|
| `GET /block-search` | `get_block_by_op` | Search blocks by operation type, account, time range |

### Account Endpoints

| Endpoint | Function | Description |
|----------|----------|-------------|
| `GET /accounts/{account-name}` | `get_account` | Full account info with balances |
| `GET /accounts/{account-name}/authority` | `get_account_authority` | Account keys and authorities |
| `GET /accounts/{account-name}/operations/comments/{permlink}` | `get_comment_operations` | Operations for a specific post |
| `GET /accounts/{account-name}/comments` | `get_comment_permlinks` | List of posts/comments by account |
| `GET /accounts/{account-name}/proxies` | `get_account_proxies_power` | Account proxy power chain |
| `GET /total_wallet_addresses` | `get_total_wallet_addresses` | Daily/monthly/yearly new-wallet counts plus cumulative chain total |

### Witness Endpoints

| Endpoint | Function | Description |
|----------|----------|-------------|
| `GET /witnesses` | `get_witnesses` | List all witnesses with pagination |
| `GET /witnesses/{account-name}` | `get_witness` | Single witness info |
| `GET /witnesses/{account-name}/voters` | `get_witness_voters` | Accounts voting for witness |
| `GET /witnesses/{account-name}/voters/num` | `get_witness_voters_num` | Count of witness voters |
| `GET /witnesses/{account-name}/votes-history` | `get_witness_votes_history` | Historical vote changes |

### Proposal Endpoints

| Endpoint | Function | Description |
|----------|----------|-------------|
| `GET /proposals/{proposal-id}/votes/history` | `get_proposal_votes_history` | Historical votes cast for a proposal |

### Transaction Endpoints

| Endpoint | Function | Description |
|----------|----------|-------------|
| `GET /transaction-statistics` | `get_transaction_statistics` | Aggregated tx stats (daily/monthly/yearly) |

### Other Endpoints

| Endpoint | Function | Description |
|----------|----------|-------------|
| `GET /version` | `get_hafbe_version` | HAFBE git commit hash |
| `GET /headblock` | `get_hafbe_last_synced_block` | Last synced block number |
| `GET /operation-type-counts` | `get_latest_blocks` | Operation histogram for recent blocks |
| `GET /input-type/{input-value}` | `get_input_type` | Detect input type (block/tx/account) |

## Submodule Endpoints

HAFBE integrates endpoints from submodules. These are exposed through HAFBE but documented separately:

| Submodule | Endpoint Prefix | Documentation |
|-----------|-----------------|---------------|
| btracker | `/rpc/btracker_*` | `submodules/btracker/scripts/claude/endpoints.md` |
| reptracker | `/rpc/reptracker_*` | `submodules/reptracker/scripts/claude/endpoints.md` |
| hafah | `/rpc/hafah_*` | `submodules/hafah/CLAUDE.md` (basic docs only) |

## Directory Structure

```
endpoints/
├── endpoint_schema.sql      # OpenAPI header, root function, aggregated spec
├── accounts/                # Account endpoint definitions
│   ├── get_account.sql
│   ├── get_account_authority.sql
│   ├── get_comment_operations.sql
│   ├── get_comment_permlinks.sql
│   ├── get_account_proxies_power.sql
│   └── get_total_wallet_addresses.sql
├── witnesses/               # Witness endpoint definitions
│   ├── get_witness.sql
│   ├── get_witnesses.sql
│   ├── get_witness_voters.sql
│   ├── get_witness_voters_num.sql
│   └── get_witness_votes_history.sql
├── proposals/               # Proposal endpoint definitions
│   └── get_proposal_votes_history.sql
├── block-search/            # Block search endpoints
│   └── get_block_by_op.sql
├── transactions/            # Transaction endpoints
│   └── get_transaction_statistics.sql
├── other/                   # Utility endpoints
│   ├── get_hafbe_version.sql
│   ├── get_hafbe_last_synced_block.sql
│   ├── get_latest_blocks.sql
│   └── get_input_type.sql
├── types/                   # SQL type definitions with OpenAPI schemas
│   ├── accounts.sql
│   ├── witnesses.sql
│   ├── blocks.sql
│   ├── transactions.sql
│   ├── operations.sql
│   ├── proposals.sql
│   └── enums.sql
└── rewrite_rules.conf       # Nginx URL rewrites for REST paths
```

## Common Patterns

### Pagination

Most list endpoints use consistent pagination:
```sql
"page" INT = 1,           -- Page number (1-indexed)
"page-size" INT = 100,    -- Items per page (max 1000)
"direction" sort_direction = 'desc'  -- 'asc' or 'desc'
```

### Block Range Filtering

Many endpoints accept block ranges via timestamp or block number:
```sql
"from-block" TEXT = NULL,  -- Block num or timestamp 'YYYY-MM-DD HH:MI:SS'
"to-block" TEXT = NULL
```
Conversion handled by `hive.convert_to_blocks_range()`.

### Response Caching

Endpoints set `Cache-Control` headers:
- Immutable data (historical): `max-age=31536000` (1 year)
- Live data: `max-age=2` (2 seconds)

### Return Types

Endpoints return custom composite types defined in `endpoints/types/`:
```sql
RETURNS hafbe_backend.account           -- Single object
RETURNS SETOF hafbe_backend.witness     -- Array of objects
RETURNS hafbe_backend.block_history     -- Paginated result with metadata
```

## Helper Functions

Endpoint logic is implemented in `backend/endpoint_helpers/`:

| Helper File | Used By | Purpose |
|-------------|---------|---------|
| `account_parameters.sql` | Account endpoints | Query account state |
| `account_hbd_interest.sql` | `get_account` | Pending HBD interest computed from balance history |
| `total_wallet_addresses.sql` | `get_total_wallet_addresses` endpoint | Wallet-count aggregation from `account_parameters` |
| `witness.sql` | Witness endpoints | Witness data retrieval |
| `blocksearch.sql` | Block search | Operation filtering logic |

## Detailed Documentation

For implementation details of each endpoint category:

| Category | Documentation |
|----------|---------------|
| Block Search | [endpoints/blocks.md](endpoints/blocks.md) |
| Accounts | [endpoints/accounts.md](endpoints/accounts.md) |
| Witnesses | [endpoints/witnesses.md](endpoints/witnesses.md) |
| Transactions | [endpoints/transactions.md](endpoints/transactions.md) |

## How to Add an Endpoint

### Step 1: Create the SQL file

Create a new file in the appropriate category directory:
```
endpoints/<category>/<function_name>.sql
```

### Step 2: Add OpenAPI annotation

Include the OpenAPI path definition:
```sql
SET ROLE hafbe_owner;

/** openapi:paths
/<your-path>:
  get:
    tags:
      - <Category>
    summary: Short description
    description: |
      Detailed description with examples

      SQL example
      * `SELECT * FROM hafbe_endpoints.your_function(...);`

      REST call example
      * `GET 'https://%1$s/hafbe-api/<your-path>'`
    operationId: hafbe_endpoints.your_function
    parameters:
      - in: path/query
        name: param-name
        required: true/false
        schema:
          type: string/integer
        description: Parameter description
    responses:
      '200':
        description: Success response
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/your_type'
      '404':
        description: Not found
*/
```

### Step 3: Define the function

Use the code generation markers:
```sql
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.your_function;
CREATE OR REPLACE FUNCTION hafbe_endpoints.your_function(
    "param-name" TEXT
)
RETURNS your_return_type
-- openapi-generated-code-end
LANGUAGE 'plpgsql'
STABLE
AS
$$
BEGIN
  -- Set cache headers
  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

  -- Your logic here
  RETURN ...;
END
$$;

RESET ROLE;
```

### Step 4: Add return type (if new)

If your endpoint returns a new type, define it in `endpoints/types/<category>.sql`:
```sql
/** openapi:components:schemas
hafbe_backend.your_type:
  type: object
  properties:
    field1:
      type: string
*/
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.your_type CASCADE;
CREATE TYPE hafbe_backend.your_type AS (
    "field1" TEXT
);
-- openapi-generated-code-end
```

### Step 5: Add URL rewrite (optional)

For RESTful paths, add to `endpoints/rewrite_rules.conf`:
```
rewrite ^/hafbe-api/your-path$ /hafbe-api/rpc/your_function break;
```

### Step 6: Install and test

```bash
# Apply changes
./scripts/install_app.sh --host=<db_host>

# Test endpoint
curl "http://localhost:3000/rpc/your_function?param-name=value"
```

## Expansion Rules

| Change Type | Action |
|-------------|--------|
| New endpoint in existing category | Add SQL file, update category's .md in `scripts/claude/endpoints/` |
| New endpoint category | Create directory, add SQL files, create new .md, update this index |
| New return type | Add to appropriate `endpoints/types/*.sql` |
| URL route change | Update `endpoints/rewrite_rules.conf` |

When modifying endpoints:
1. Update the SQL file with OpenAPI annotations
2. Update the corresponding documentation in `scripts/claude/endpoints/`
3. Ensure return types are properly documented in `endpoints/types/`
