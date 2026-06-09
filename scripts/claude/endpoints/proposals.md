# Proposal Endpoints

Proposal endpoints expose DHF (Decentralised Hive Fund) proposal data including proposal listings, current vote approvals, and the full history of vote events.

## Endpoints

### GET /proposals

**Function:** `hafbe_endpoints.get_proposals`
**File:** `endpoints/proposals/get_proposals.sql`

List proposals with paid amounts and stake-weighted vote totals.

#### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `page` | INT | No | 1 | Page number |
| `page-size` | INT | No | 100 | Results per page (max 1000) |
| `sort` | order_by_proposal | No | by_total_votes | Sort key (see below) |
| `direction` | sort_direction | No | desc | Sort order |
| `status` | proposal_status | No | all | Filter by proposal status |
| `creator` | TEXT | No | NULL | Filter to proposals created by this account |
| `proposal-ids` | TEXT | No | NULL | Comma-separated list of proposal IDs to return |
| `voter` | TEXT | No | NULL | Filter to proposals currently approved by this voter account |
| `search` | TEXT | No | NULL | Exact-match filter on proposal subject |

**Sort options:**
- `by_total_votes` — stake-weighted vote total (descending = highest first)
- `by_creator` — creator account name
- `by_start_date` — proposal start date
- `by_end_date` — proposal end date

**Status options:**
- `all` — any non-removed proposal
- `active` — currently payable (`start_date <= now <= end_date`)
- `inactive` — not yet started (`now < start_date`)
- `expired` — finished (`now > end_date`)
- `votable` — active or inactive (`now <= end_date`)

#### Response

Returns `hafbe_backend.proposals_return`:
```json
{
  "total_proposals": 42,
  "total_pages": 1,
  "proposals": [
    {
      "id": 9001,
      "proposal_id": 9001,
      "creator": "alice",
      "receiver": "alice",
      "start_date": "2019-11-05T00:00:00",
      "end_date": "2020-11-05T00:00:00",
      "daily_pay": "100000",
      "subject": "My proposal",
      "permlink": "my-proposal",
      "total_votes": "1234567890",
      "voters_num": 12,
      "paid_amount": "36500000",
      "status": "active"
    }
  ]
}
```

#### Notes

- `total_votes` is stake-weighted by governance vesting power of direct voters only (proxied voters are excluded — this matches condenser_api behaviour but differs from the raw voter count)
- `paid_amount` is a running total incremented by each `proposal_pay_operation` processed by the block processor; it starts at 0 for new proposals
- The `creator`, `proposal-ids`, `voter`, and `search` filters are optional and composable; account names are resolved to IDs via `hafah_backend.get_account_id` before querying

---

### GET /proposals/votes

**Function:** `hafbe_endpoints.get_proposal_votes`
**File:** `endpoints/proposals/get_proposal_votes.sql`

Current active approvals for proposals (one row per voter currently approving a proposal).

#### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `page` | INT | No | 1 | Page number |
| `page-size` | INT | No | 100 | Results per page (max 1000) |
| `sort` | order_by_proposal_vote | No | by_proposal_voter | Sort key |
| `direction` | sort_direction | No | asc | Sort order |
| `status` | proposal_status | No | all | Filter votes by the joined proposal's status |
| `proposal-id` | INT | No | NULL | Filter to votes for this proposal ID only |
| `voter` | TEXT | No | NULL | Filter to votes cast by this account only |

**Sort options:**
- `by_voter_proposal` — voter account, then proposal ID
- `by_proposal_voter` — proposal ID, then voter account

#### Response

Returns `hafbe_backend.proposal_votes_return`:
```json
{
  "total_votes": 12,
  "total_pages": 1,
  "votes": [
    {
      "voter_name": "alice",
      "proposal": {
        "id": 9001,
        "proposal_id": 9001,
        "creator": "bob",
        "receiver": "bob",
        "start_date": "2019-11-05T00:00:00",
        "end_date": "2020-11-05T00:00:00",
        "daily_pay": "100000",
        "subject": "My proposal",
        "permlink": "my-proposal",
        "total_votes": "1234567890",
        "voters_num": 12,
        "paid_amount": "36500000",
        "status": "active"
      },
      "voter_vests": "5000000000000",
      "direct_vests": "5000000000000",
      "proxied_vests": "0",
      "proxy": "",
      "timestamp": "2019-11-05T10:12:09"
    }
  ]
}
```

#### Notes

- `voter_vests` — effective governance VESTS for this voter at last cache refresh; **0 if the voter currently has a proxy set** (their power flows through the proxy instead)
- `direct_vests` — this voter's own governance VESTS (`account_vests`), independent of any proxy
- `proxied_vests` — VESTS from other accounts that have **proxied their governance to this voter** (i.e. this voter is acting as their proxy)
- `proxy` — name of the governance proxy this voter has delegated to; **empty string `""`** if no proxy is set (not null)
- `proposal` — full nested proposal object (same as `hafbe_backend.proposal`); mirrors `condenser_api.ProposalVote.proposal` so the front end can display proposal details without a second request
- `timestamp` — block timestamp at which this active vote was last (re)cast

---

### GET /proposals/{proposal-id}/votes/history

**Function:** `hafbe_endpoints.get_proposal_votes_history`
**File:** `endpoints/proposals/get_proposal_votes_history.sql`

Full chronological history of vote events for a proposal — includes both approvals (`approve=true`) and later withdrawals (`approve=false`). Explicit unvotes come from `update_proposal_votes_operation`; additional withdrawal rows are synthesised by `process_proposals()` when a proposal is removed or when an account declines/loses voting rights.

#### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `proposal-id` | INT | Yes | — | Proposal ID to fetch history for |
| `voter-name` | TEXT | No | NULL | Filter to events for this voter account only |
| `page` | INT | No | 1 | Page number |
| `page-size` | INT | No | 100 | Results per page (max **10000** — higher than other proposal endpoints because history rows per voter can far exceed unique voter count) |
| `direction` | sort_direction | No | desc | Sort order (newest first by default) |
| `from-block` | TEXT | No | NULL | Lower bound: block number or `YYYY-MM-DD HH:MI:SS` timestamp |
| `to-block` | TEXT | No | NULL | Upper bound: block number or `YYYY-MM-DD HH:MI:SS` timestamp |

#### Response

Returns `hafbe_backend.proposal_votes_history`:
```json
{
  "total_votes": 12,
  "total_pages": 1,
  "votes_history": [
    {
      "voter_name": "alice",
      "approve": true,
      "own_vests": "1000000",
      "proxied_vests": "0",
      "delayed_vests": "0",
      "timestamp": "2019-11-05T10:12:09"
    },
    {
      "voter_name": "alice",
      "approve": false,
      "own_vests": "1000000",
      "proxied_vests": "0",
      "delayed_vests": "0",
      "timestamp": "2019-11-06T08:43:21"
    }
  ]
}
```

#### Notes

- The `page-size` limit is 10000 (not 1000) because vote history accumulates over the full lifecycle of a proposal; a single voter can appear multiple times (vote → unvote → revote)
- Vote history rows include the voter's current-head governance stake: `own_vests` (gross VESTS balance), `proxied_vests` (VESTS proxied to this voter by others), `delayed_vests` (pending power-down withdrawals). Effective governance power = `own_vests - delayed_vests + proxied_vests`. All three are evaluated at the current HAFBE processed head block — not snapshotted at vote time.
- `from-block` / `to-block` accept either integer block numbers or ISO-style timestamps; timestamps are converted to block numbers by the block time index

---

## Data Sources

| Table | Populated by | Description |
|-------|-------------|-------------|
| `hafbe_app.current_proposals` | `process_proposals()` | Proposal metadata mirror; `paid_amount` is a running total |
| `hafbe_app.current_proposal_votes` | `process_proposals()` | Active approvals (one row per currently-approving voter) |
| `hafbe_app.proposal_votes_history` | `process_proposals()` | All vote events including synthetic `approve=FALSE` rows |
| `hafbe_app.proposal_payments` | `process_proposals()` | Append-only per-payment audit ledger |
| `hafbe_app.proposal_vote_stats_cache` | `process_proposal_vote_stats_cache()` | Stake-weighted totals + voter count per proposal (LIVE cache) |

See `scripts/claude/processing.md` for the processor detail.

## Testing

Proposal endpoints are covered by:
- **SQL assertions**: `tests/mocks/sql/verify.sql` (36 checks run by `verify_mock_data.sh`)
- **Tavern HTTP tests**: `tests/tavern/patterns-mock/` (35 test cases with matching `.pat.json` files, run by `pattern-test-with-mock-data` CI job)

Both use a synthetic 91M block range because DHF proposals only appear on mainnet past block ~22.3M (HF21). See `scripts/claude/tests.md` for the mock harness workflow.
