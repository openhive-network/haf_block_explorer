# Witness Endpoints

Witness endpoints provide information about Hive witnesses including rankings, votes, properties, and historical data.

## Endpoints

### GET /witnesses

**Function:** `hafbe_endpoints.get_witnesses`
**File:** `endpoints/witnesses/get_witnesses.sql`

List all witnesses (active and standby) with pagination and sorting.

#### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `page` | INT | No | 1 | Page number |
| `page-size` | INT | No | 100 | Results per page (max 1000) |
| `sort` | order_by_witness | No | votes | Sort key (see below) |
| `direction` | sort_direction | No | desc | Sort order |

**Sort options:**
- `witness` - Witness name
- `rank` - Current rank
- `url` - Witness URL
- `votes` - Total vote weight
- `votes_daily_change` - 24h vote change
- `voters_num` - Number of voters
- `voters_num_daily_change` - 24h voter count change
- `price_feed` - Current price feed
- `feed_updated_at` - Feed timestamp
- `bias` - Price feed bias
- `block_size` - Voted block size
- `signing_key` - Signing public key
- `version` - hived version

#### Response

Returns `hafbe_backend.witnesses_return`:
```json
{
  "total_witnesses": 731,
  "total_pages": 366,
  "witnesses": [
    {
      "witness_name": "blocktrades",
      "rank": 1,
      "url": "https://blocktrades.us",
      "vests": "82373419958692803",
      "votes_daily_change": "0",
      "voters_num": 263,
      "voters_num_daily_change": 0,
      "price_feed": 0.545,
      "bias": 0,
      "feed_updated_at": "2016-09-15T16:02:21",
      "block_size": 65536,
      "signing_key": "STM4vmVc3rErkueyWNddyGfmjmLs3Rr4i7YJi8Z7gFeWhakXM4nEz",
      "version": "0.13.0",
      "missed_blocks": 935,
      "hbd_interest_rate": 1000,
      "last_confirmed_block_num": 4999992,
      "account_creation_fee": 9000
    }
  ]
}
```

#### Example

```bash
# Get top 20 witnesses by votes
curl "http://localhost:3000/hafbe-api/witnesses?page-size=20"

# Sort by missed blocks descending
curl "http://localhost:3000/hafbe-api/witnesses?sort=missed_blocks&direction=desc"

# Get witnesses sorted by name
curl "http://localhost:3000/hafbe-api/witnesses?sort=witness&direction=asc"
```

---

### GET /witnesses/{account-name}

**Function:** `hafbe_endpoints.get_witness`
**File:** `endpoints/witnesses/get_witness.sql`

Get detailed information about a single witness.

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `account-name` | TEXT | Yes | Witness account name |

#### Response

Returns `hafbe_backend.witness`:
```json
{
  "witness_name": "blocktrades",
  "rank": 8,
  "url": "https://blocktrades.us",
  "vests": "82373419958692803",
  "votes_daily_change": "0",
  "voters_num": 263,
  "voters_num_daily_change": 0,
  "price_feed": 0.545,
  "bias": 0,
  "feed_updated_at": "2016-09-15T16:02:21",
  "block_size": 65536,
  "signing_key": "STM4vmVc3rErkueyWNddyGfmjmLs3Rr4i7YJi8Z7gFeWhakXM4nEz",
  "version": "0.13.0",
  "missed_blocks": 935,
  "hbd_interest_rate": 1000,
  "last_confirmed_block_num": 4999992,
  "account_creation_fee": 9000
}
```

#### Example

```bash
curl "http://localhost:3000/hafbe-api/witnesses/blocktrades"
```

---

### GET /witnesses/{account-name}/voters

**Function:** `hafbe_endpoints.get_witness_voters`
**File:** `endpoints/witnesses/get_witness_voters.sql`

List accounts that have voted for a witness.

#### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `account-name` | TEXT | Yes | - | Witness account name |
| `page` | INT | No | 1 | Page number |
| `page-size` | INT | No | 100 | Results per page |
| `sort` | order_by_votes | No | vests | Sort key |
| `direction` | sort_direction | No | desc | Sort order |

**Sort options:**
- `voter` - Voter account name
- `vests` - Voter's vesting shares
- `account_vests` - Direct account vests
- `proxied_vests` - Proxied voting power
- `timestamp` - Vote timestamp

#### Response

Returns `hafbe_backend.witness_voters_return`:
```json
{
  "total_voters": 263,
  "total_pages": 3,
  "voters": [
    {
      "voter": "alice",
      "vests": "1000000000000",
      "account_vests": "800000000000",
      "proxied_vests": "200000000000",
      "timestamp": "2020-01-01T00:00:00"
    }
  ]
}
```

---

### GET /witnesses/{account-name}/voters/num

**Function:** `hafbe_endpoints.get_witness_voters_num`
**File:** `endpoints/witnesses/get_witness_voters_num.sql`

Get the count of accounts voting for a witness.

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `account-name` | TEXT | Yes | Witness account name |

#### Response

Returns `INT`:
```json
263
```

---

### GET /witnesses/{account-name}/votes-history

**Function:** `hafbe_endpoints.get_witness_votes_history`
**File:** `endpoints/witnesses/get_witness_votes_history.sql`

Get historical vote changes for a witness.

#### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `account-name` | TEXT | Yes | - | Witness account name |
| `page` | INT | No | 1 | Page number |
| `page-size` | INT | No | 100 | Results per page |
| `sort` | order_by_votes | No | timestamp | Sort key |
| `direction` | sort_direction | No | desc | Sort order |
| `from-block` | TEXT | No | NULL | Lower block bound |
| `to-block` | TEXT | No | NULL | Upper block bound |

#### Response

Returns `hafbe_backend.witness_votes_history_return`:
```json
{
  "total_votes": 1500,
  "total_pages": 15,
  "votes_history": [
    {
      "voter": "alice",
      "approve": true,
      "vests": "1000000000000",
      "account_vests": "800000000000",
      "proxied_vests": "200000000000",
      "timestamp": "2020-01-01T00:00:00"
    }
  ]
}
```

#### Ordering

Sorted by `(source_op_block, voter_id, source_op)`. The `source_op` key is **required for
correctness, not a cosmetic tie-break**: a Hive block is 3 seconds and nothing stops an account
from voting and un-voting the same witness inside one block, which produces two history rows
identical on `(source_op_block, voter_id)`. Tied rows have no defined order, so without
`source_op` the un-vote could be returned *before* the vote it undid, and the two sorts in
`hafbe_backend.get_witness_votes_history` (one inside `limited_set` to pick the page, one after
the `UNION ALL` to display it) could break the same tie in opposite directions — making the row
order depend on the page size. `source_op` is the operation id: monotonic within a block and
unique, so the sort is total.

Real example: `cmtzco` voted for `arhag` and un-voted in block 3067986. Covered by
`tests/tavern/patterns-mainnet/get_witness_votes_history/positive/tied_same_block_vote_unvote.*`.
The same rule is applied in `get_proposal_votes_history`; see `proposals.md`.

## Return Types

All witness types are defined in `endpoints/types/witnesses.sql`:

| Type | Description |
|------|-------------|
| `hafbe_backend.witness` | Single witness data |
| `hafbe_backend.witnesses_return` | Paginated witness list |
| `hafbe_backend.witness_voter` | Voter information |
| `hafbe_backend.witness_voters_return` | Paginated voters |
| `hafbe_backend.witness_vote_history` | Historical vote record |
| `hafbe_backend.witness_votes_history_return` | Paginated vote history |

## Enum Types

Defined in `endpoints/types/enums.sql`:

| Enum | Values |
|------|--------|
| `order_by_witness` | witness, rank, url, votes, votes_daily_change, voters_num, etc. |
| `order_by_votes` | voter, vests, account_vests, proxied_vests, timestamp |

## Helper Functions

Located in `backend/endpoint_helpers/witness.sql`:

| Function | Purpose |
|----------|---------|
| `get_witness()` | Retrieve witness data by ID |
| `get_witness_id()` | Convert name to witness ID |
| `get_witnesses()` | Paginated witness list |
| `get_witnesses_count()` | Total witness count |
| `get_witness_voters()` | Voters for a witness |
| `get_witness_votes_history()` | Historical votes |

## Cache Tables

Witness endpoints use cache tables for performance (updated in LIVE mode):

| Table | Purpose |
|-------|---------|
| `hafbe_app.witness_votes_cache` | Total votes per witness |
| `hafbe_app.witness_rank_cache` | Witness rankings |
| `hafbe_app.witness_votes_change_cache` | 24h vote changes |
| `hafbe_app.account_vest_stats_cache` | Voter vesting power |

## Related Processing

Witness data is populated by:
- `process_witness_stats()` - Witness properties
- `process_witness_votes()` - Votes and proxies
- `process_witness_votes_cache()` - Cache updates (LIVE mode)

See [processing/witnesses.md](../processing/witnesses.md) and [processing/witness_votes.md](../processing/witness_votes.md).

## Key Tables

| Table | Purpose |
|-------|---------|
| `hafbe_app.current_witnesses` | Active witness properties |
| `hafbe_app.witness_votes_history` | Vote change log |
| `hafbe_app.current_witness_votes` | Active votes |
| `hafbe_app.account_proxies_history` | Proxy change log |
| `hafbe_app.current_account_proxies` | Active proxies |

## Adding a Witness Endpoint

1. Create SQL file in `endpoints/witnesses/`
2. Add OpenAPI annotation with `Witnesses` tag
3. Use existing helper functions from `backend/endpoint_helpers/witness.sql`
4. Define return type in `endpoints/types/witnesses.sql` if needed
5. Add URL rewrite to `endpoints/rewrite_rules.conf`
6. Update this documentation
