# Witness Votes Processing

**Source**: `db/process_witness_votes.sql`
**Functions**:
- `hafbe_app.process_witness_votes(_from INT, _to INT)`
- `hafbe_app.process_witness_votes_cache()` (LIVE mode only)

## Purpose

Processes witness vote and proxy operations. Unlike other processors, this requires **row-by-row processing** due to complex interdependencies between operations.

## Why Row-by-Row Processing

Operations have cascading effects that require sequential processing:

1. Setting a proxy **deletes all existing witness votes** for that account
2. Clearing a proxy allows the account to vote directly again
3. Expired/declined accounts lose **all votes and proxies**

**Example sequence that MUST be processed in order:**
```
Op 100: Vote for witness A
Op 200: Set proxy to X (cascade: deletes vote for A)
Op 300: Clear proxy
Op 400: Vote for witness B
```

**Correct final state:** Only vote for B exists

**If processed as batch:**
- Section 1: Insert votes for A and B
- Section 2: Set proxy (deletes ALL votes including B!)
- **Wrong final state:** No votes

## Operations Processed

| Operation Type | Handler Function | Effect |
|----------------|-----------------|--------|
| `account_witness_vote` | `process_vote_op()` | Add/remove witness vote |
| `account_witness_proxy` | `process_proxy_ops(..., TRUE)` | Set proxy + cascade delete votes |
| `proxy_cleared` | `process_proxy_ops(..., FALSE)` | Clear proxy |
| `declined_voting_rights` | `process_expired_accounts()` | Delete all votes and proxies |
| `expired_account_notification` | `process_expired_accounts()` | Delete all votes and proxies |

## Tables Updated

### History Tables (append-only)
| Table | Purpose |
|-------|---------|
| `hafbe_app.witness_votes_history` | Complete vote change log |
| `hafbe_app.account_proxies_history` | Complete proxy change log |

### Current State Tables
| Table | Purpose |
|-------|---------|
| `hafbe_app.current_witness_votes` | Active witness votes |
| `hafbe_app.current_account_proxies` | Active proxy assignments |

### Cache Tables (LIVE only)
| Table | Purpose |
|-------|---------|
| `hafbe_app.account_vest_stats_cache` | Vesting power per account |
| `hafbe_app.witness_votes_cache` | Total votes per witness |
| `hafbe_app.witness_rank_cache` | Witness rankings |
| `hafbe_app.witness_votes_change_cache` | 24h vote changes |

## Handler Functions

Located in `backend/operation_parsers/witness_operations.sql`:

### `process_vote_op(_body, _id)`

Processes `account_witness_vote_operation`:

```sql
-- JSON: { "value": { "account": "voter", "witness": "witness-name", "approve": true/false } }

-- Always record in history
INSERT INTO witness_votes_history ...

-- Update current state
IF approve THEN
  INSERT INTO current_witness_votes ON CONFLICT DO UPDATE
ELSE
  DELETE FROM current_witness_votes
END IF
```

### `process_proxy_ops(_body, _id, _proxy)`

Processes `account_witness_proxy_operation` and `proxy_cleared_operation`:

```sql
-- JSON: { "value": { "account": "account-name", "proxy": "proxy-name" } }

-- Record in history
INSERT INTO account_proxies_history ...

IF _proxy (setting proxy) THEN
  -- Upsert proxy
  INSERT INTO current_account_proxies ON CONFLICT DO UPDATE

  -- CASCADE: Delete all witness votes for this account
  DELETE FROM current_witness_votes WHERE voter_id = account_id
  -- Record deleted votes in history as approve=FALSE
  INSERT INTO witness_votes_history (approve=FALSE)
ELSE (clearing proxy)
  DELETE FROM current_account_proxies
END IF
```

### `process_expired_accounts(_body, _id)`

Processes `declined_voting_rights_operation` and `expired_account_notification_operation`:

```sql
-- JSON: { "value": { "account": "account-name" } }

-- Delete all proxies and record in history
DELETE FROM current_account_proxies WHERE account_id = ...
INSERT INTO account_proxies_history (proxy=FALSE)

-- Delete all witness votes and record in history
DELETE FROM current_witness_votes WHERE voter_id = ...
INSERT INTO witness_votes_history (approve=FALSE)
```

## Cache Processing (LIVE only)

`process_witness_votes_cache()` runs after all other processors in LIVE mode:

### Cache 1: Account Vest Stats
```sql
DELETE FROM account_vest_stats_cache;
INSERT FROM hafbe_backend.account_vest_stats_view;
-- Contains: account_id, vests (total), account_vests (own), proxied_vests
```

### Cache 2: Witness Votes
```sql
DELETE FROM witness_votes_cache;
INSERT SELECT witness_id, SUM(vests), COUNT(*) FROM current_witness_votes
  JOIN account_vest_stats_cache;
```

### Cache 3: Witness Rank
```sql
DELETE FROM witness_rank_cache;
INSERT SELECT witness_id, ROW_NUMBER() OVER (ORDER BY votes DESC, voters_num DESC);
```

### Cache 4: Daily Vote Changes
```sql
DELETE FROM witness_votes_change_cache;
INSERT SELECT witness_id,
  SUM(CASE WHEN approve THEN vests ELSE -vests END),
  SUM(CASE WHEN approve THEN 1 ELSE -1 END)
FROM witness_votes_history WHERE source_op_block >= first_block_of_today;
```

## Data Flow

```
operations_view
    │
    └── proxy_ops CTE (filter relevant ops)
            │
            └── balance_change CTE (process in ORDER BY id)
                    │
                    ├── process_vote_op() ─────────────────┐
                    │                                      │
                    ├── process_proxy_ops(..., TRUE) ──────┼──→ witness_votes_history
                    │                                      │     current_witness_votes
                    ├── process_proxy_ops(..., FALSE) ─────┼──→ account_proxies_history
                    │                                      │     current_account_proxies
                    └── process_expired_accounts() ────────┘
```

## How to Modify

### Adding a new vote-related operation

1. Add operation type constant to `backend/utilities/operation_types.sql`
2. Create handler function in `backend/operation_parsers/witness_operations.sql`
3. Add CASE branch in `balance_change` CTE
4. Include operation type ID in `proxy_ops` WHERE filter

### Modifying cascade behavior

The cascade logic is in `process_proxy_ops()`. Changes here affect:
- What happens when a proxy is set/cleared
- Which votes are deleted and recorded in history

**Warning:** Cascade changes are security-critical. Ensure the new behavior matches blockchain consensus rules.

### Modifying cache calculations

Cache functions use views from `hafbe_backend`:
- `account_vest_stats_view` - Vest calculations
- `current_witness_votes_view` - Active votes
- `witness_votes_history_view` - Vote history

Modify these views to change what data is cached.

## Testing

Witness vote changes can be tested via:
- `tests/regression/` - Compare against hived snapshots
- `tests/tavern/patterns-mainnet/` - API endpoint tests for witness votes
