# Account Endpoints

Account endpoints provide information about Hive accounts including balances, authorities, operations, and proxy relationships.

## Endpoints

### GET /accounts/{account-name}

**Function:** `hafbe_endpoints.get_account`
**File:** `endpoints/accounts/get_account.sql`

Get comprehensive account information including balances, metadata, and voting data.

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `account-name` | TEXT | Yes | Account name (path parameter) |

#### Response

Returns `hafbe_backend.account`:
```json
{
  "id": 440,
  "name": "blocktrades",
  "can_vote": true,
  "mined": true,
  "proxy": "",
  "recovery_account": "steem",
  "last_account_recovery": "1970-01-01T00:00:00",
  "created": "2016-03-30T00:04:36",
  "reputation": 69,
  "pending_claimed_accounts": 0,
  "json_metadata": "",
  "posting_json_metadata": "",
  "profile_image": "",
  "hbd_balance": 77246982,
  "balance": 29594875,
  "vesting_shares": "8172549681941451",
  "vesting_balance": 2720696229,
  "hbd_saving_balance": 0,
  "savings_balance": 0,
  "savings_withdraw_requests": 0,
  "reward_hbd_balance": 0,
  "reward_hive_balance": 0,
  "reward_vesting_balance": "0",
  "reward_vesting_hive": 0,
  "posting_rewards": "65916519",
  "curation_rewards": "196115157",
  "delegated_vesting_shares": "0",
  "received_vesting_shares": "0",
  "proxied_vsf_votes": ["4983403929606734", "0", "0", "0"],
  "withdrawn": "804048182205290",
  "vesting_withdraw_rate": "80404818220529",
  "to_withdraw": "8362101094935031",
  "withdraw_routes": 4,
  "delayed_vests": "0",
  "witness_votes": ["blocktrades", "gtg", ...],
  "witnesses_voted_for": 9,
  "ops_count": 219867,
  "is_witness": true
}
```

#### Example

```bash
curl "http://localhost:3000/hafbe-api/accounts/blocktrades"
```

#### Data Sources

This endpoint aggregates data from multiple sources:
- `btracker_endpoints.get_account_balances()` - Balance data
- `reptracker_endpoints.get_account_reputation()` - Reputation score
- `hafbe_backend.get_json_metadata()` - Profile metadata
- `hafbe_backend.get_account_parameters()` - Account settings
- `hafbe_backend.get_account_witness_votes()` - Witness votes
- `hafbe_backend.get_account_proxy()` - Proxy assignment
- `hafbe_backend.get_account_ops_count()` - Operation count

---

### GET /accounts/{account-name}/authority

**Function:** `hafbe_endpoints.get_account_authority`
**File:** `endpoints/accounts/get_account_authority.sql`

Get account's cryptographic keys and authorities.

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `account-name` | TEXT | Yes | Account name (path parameter) |

#### Response

Returns `hafbe_backend.account_authority`:
```json
{
  "owner": {
    "key_auths": [["STM...", 1]],
    "account_auths": [],
    "weight_threshold": 1
  },
  "active": {
    "key_auths": [["STM...", 1]],
    "account_auths": [],
    "weight_threshold": 1
  },
  "posting": {
    "key_auths": [["STM...", 1]],
    "account_auths": [],
    "weight_threshold": 1
  },
  "memo": "STM...",
  "witness_signing": "STM..."
}
```

---

### GET /accounts/{account-name}/operations/comments/{permlink}

**Function:** `hafbe_endpoints.get_comment_operations`
**File:** `endpoints/accounts/get_comment_operations.sql`

Get operations related to a specific post/comment.

#### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `account-name` | TEXT | Yes | - | Author account name |
| `permlink` | TEXT | Yes | - | Post permlink |
| `operation-types` | TEXT | No | NULL | Filter by op types (comment-related: 0,1,17,19,51,52,53,61,63,72,73) |
| `page` | INT | No | 1 | Page number |
| `page-size` | INT | No | 100 | Results per page (max 10000) |
| `direction` | sort_direction | No | asc | Sort order |
| `data-size-limit` | INT | No | 200000 | Max operation body size |

#### Response

Returns `hafbe_backend.operation_history`:
```json
{
  "total_operations": 350,
  "total_pages": 117,
  "operations_result": [
    {
      "op": {
        "type": "vote_operation",
        "value": {
          "voter": "alice",
          "author": "blocktrades",
          "weight": 10000,
          "permlink": "my-post"
        }
      },
      "block": 4228228,
      "trx_id": "2bbeb7513e49cb169d4fe446ff980f2102f7210a",
      "op_pos": 1,
      "op_type_id": 0,
      "timestamp": "2016-08-19T21:21:03",
      "virtual_op": false,
      "operation_id": "18160100980032256",
      "trx_in_block": 1
    }
  ]
}
```

#### Example

```bash
curl "http://localhost:3000/hafbe-api/accounts/blocktrades/operations/comments/my-post?page-size=10"
```

**Note:** Requires comment search indexes to be installed.

---

### GET /accounts/{account-name}/comments

**Function:** `hafbe_endpoints.get_comment_permlinks`
**File:** `endpoints/accounts/get_comment_permlinks.sql`

List all posts and comments by an account.

#### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `account-name` | TEXT | Yes | - | Account name |
| `comment-type` | comment_type | No | all | Filter: `post`, `comment`, or `all` |
| `page` | INT | No | NULL | Page number |
| `page-size` | INT | No | 100 | Results per page |
| `direction` | sort_direction | No | desc | Sort order |
| `from-block` | TEXT | No | NULL | Lower block bound |
| `to-block` | TEXT | No | NULL | Upper block bound |

#### Response

Returns `hafbe_backend.permlink_history`:
```json
{
  "total_permlinks": 500,
  "total_pages": 5,
  "block_range": {"from": 1, "to": 5000000},
  "permlinks_result": [
    {
      "permlink": "my-first-post",
      "block": 1234567,
      "trx_id": "abc123...",
      "timestamp": "2020-01-01T00:00:00",
      "operation_id": "123456789"
    }
  ]
}
```

---

### GET /accounts/{account-name}/proxies

**Function:** `hafbe_endpoints.get_account_proxies_power`
**File:** `endpoints/accounts/get_account_proxies_power.sql`

Get accounts that have proxied their voting power to this account.

#### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `account-name` | TEXT | Yes | - | Account name |
| `page` | INT | No | 1 | Page number |
| `sort` | order_by_proxy | No | proxy_date | Sort field: `account`, `proxy_date`, `proxied_vests` |
| `direction` | sort_direction | No | desc | `asc` or `desc` |

#### Response

Returns array of `hafbe_backend.proxy_power`:
```json
[
  {
    "account": "alice",
    "proxy_date": "2020-01-01T00:00:00",
    "proxied_vests": "1000000000"
  }
]
```

### GET /total_wallet_addresses

**Function:** `hafbe_endpoints.get_total_wallet_addresses`
**File:** `endpoints/accounts/get_total_wallet_addresses.sql`

Chain-wide wallet (account) creation counts grouped by period plus a running cumulative total. Powers live wallet-count tickers and chain-growth charts.

#### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `granularity` | granularity | No | yearly | Aggregation period: `daily`, `monthly`, `yearly` |
| `direction` | sort_direction | No | desc | Sort order: `asc` or `desc` |
| `from-block` | TEXT | No | NULL | Start block number or ISO timestamp |
| `to-block` | TEXT | No | NULL | End block number or ISO timestamp |

#### Response

Returns array of `hafbe_backend.wallet_stats`:
```json
[
  {
    "date": "2016-09-01T00:00:00",
    "new_wallets": 37107,
    "total_wallets": 80302
  }
]
```

Cache-Control: `max-age=2` for live head data; `max-age=31536000` for fully irreversible ranges.

## Return Types

All account types are defined in `endpoints/types/accounts.sql`:

| Type | Description |
|------|-------------|
| `hafbe_backend.account` | Full account data |
| `hafbe_backend.account_authority` | Keys and authorities |
| `hafbe_backend.authority_type` | Authority structure |
| `hafbe_backend.permlink` | Post/comment reference |
| `hafbe_backend.permlink_history` | Paginated permlinks |
| `hafbe_backend.proxy_power` | Proxy relationship |
| `hafbe_backend.wallet_stats` | Per-period new + cumulative wallet counts (used by `get_total_wallet_addresses`) |

## Helper Functions

Located in `backend/endpoint_helpers/`:

| Function | File | Purpose |
|----------|------|---------|
| `get_account_parameters()` | `account_parameters.sql` | Account settings |
| `get_json_metadata()` | `account_parameters.sql` | Profile metadata |
| `get_account_witness_votes()` | `account_parameters.sql` | Witness vote list |
| `get_account_proxy()` | `account_parameters.sql` | Proxy assignment |
| `get_account_ops_count()` | `account_parameters.sql` | Operation count |
| `get_account_proxied_vsf_votes()` | `account_parameters.sql` | Recursive proxy power |
| `parse_profile_picture()` | `account_parameters.sql` | Extract profile image URL |
| `get_total_wallet_address_aggregation()` | `total_wallet_addresses.sql` | Date-series aggregation of account creation counts with running cumulative sum |

## Related Processing

Account data is populated by:
- `process_account_stats()` - Account parameters
- Balance Tracker (btracker) - Balance data
- Reputation Tracker (reptracker) - Reputation scores

See [processing/accounts.md](../processing/accounts.md) for details.

## Adding an Account Endpoint

1. Create SQL file in `endpoints/accounts/`
2. Add OpenAPI annotation with `Accounts` tag
3. Use existing helper functions or create new ones in `backend/endpoint_helpers/`
4. Define return type in `endpoints/types/accounts.sql` if needed
5. Add URL rewrite to `endpoints/rewrite_rules.conf`
6. Update this documentation
