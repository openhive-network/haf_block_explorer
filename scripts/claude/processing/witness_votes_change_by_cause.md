# Witness Vote Change by Cause

**Source**: `db/process_witness_votes_change_by_cause.sql`
**Functions**:
- `hafbe_app.process_witness_votes_change_by_cause(_block INT)` (LIVE, from `single_processing()`)
- `hafbe_app.process_witness_votes_change_by_cause()` (refresh at the context's block: CI's sync, `.aidev/run-checks.sh`; the first LIVE block refreshes through `(_block)`, having no state row)
- `hafbe_app.refresh_witness_votes_change_by_cause(_block INT)`
- `hafbe_app.witness_votes_change_by_cause_of(_first_block INT)` (one window, one set-based pass)
- `hafbe_app.witness_votes_change_week_start(_block INT)`
- `hafbe_app.witness_votes_change_by_cause_indexes_ready()`

**Tables**: `hafbe_app.witness_votes_change_by_cause (witness_id, time_window, cause, vests, voters)`,
`hafbe_app.witness_votes_change_by_cause_state (as_of_block, today_first_block, week_first_block)`.
Neither is registered with HAF (like the witness vote caches).

## Purpose

`votes_daily_change` counts only today's votes, at the voters' current weight. A witness's
`vests` also moves every block (producer rewards, claimed rewards) and with power-downs and
matured power-ups. This breaks each witness's change down by cause, over **today** (the
daily-change window, `witness_votes_cache_window_start()`) and **7d** (from the last block
at or before `as_of_block`'s time minus 7 days), for `votes_change_breakdown` on `/witnesses`.

## Schedule

`single_processing()` calls `process_witness_votes_change_by_cause(_block)` last. It refreshes
when `_block % 100 = 0`, when there is no state row yet, or when the state's `as_of_block` is
at or above `_block` (a fork reverted the blocks it was computed from). Never during
MASSIVE_PROCESSING, and outside `process_witness_votes_cache` (#189's per-block budget).
While the balance tracker's registered `account_balance_history` indexes (`(account, nai, block)`,
`(account, nai, balance_seq_no)`) are missing or invalid (`witness_votes_change_by_cause_indexes_ready()`),
the LIVE path skips with a NOTICE and the explicit refresh raises: without them each per-account probe
scans the whole table. They exist from the switch to LIVE; a harness that stops in MASSIVE_PROCESSING
must restore them (`hive.app_restore_indexes('hafbe_bal')`, as `.aidev/run-checks.sh` and CI's sync do).
Measured on steem-20 (mainnet, ~4.5k voters, 1.9k proxies, 2026-11-16): today window ~0.2 s,
7d ~0.7-1.0 s warm, per refresh. The feeders' `account_balance_history` rows are read with one
`(account, nai, block)` probe each (a LATERAL subquery with a window function, which the planner
cannot flatten); joined, it merge-joined the whole index.

## Causes

Governance weight is `account_vest_stats()`'s: own VESTS minus delayed VESTS, plus VESTS
proxied up to 4 levels.

| cause | events |
|---|---|
| `votes_cast` / `votes_removed` | `witness_votes_history` rows of `account_witness_vote` |
| `power_down` | `account_balance_history` VESTS decreases of `fill_vesting_withdraw` (the routed recipient's credit is delayed VESTS: not counted) |
| `power_up` | `delayed_voting` operations (`votes`) |
| `producer_reward` / `claimed_reward` | `account_balance_history` VESTS changes of `producer_reward` / `claim_reward_balance` |
| `proxy` | `account_proxies_history` rows of `account_witness_proxy` / `proxy_cleared`, and the vote removals `account_witness_proxy` cascades |
| `expired` / `declined` | the vote and proxy removals of `expired_account_notification` / `declined_voting_rights` |

A balance change is `balance` minus the account's previous row (same account and nai), so
`account_balance_history` is read by `(account, nai, block)` for the accounts whose weight can
reach a witness (current voters, proxy setters, and the window's vote and proxy accounts).

## How a pass works

1. **Events**: vote rows, proxy rows (each with the proxy it replaced: the previous row, or
   the last one before the window), own-weight changes (balance rows, `delayed_voting`).
2. **Routing**: an own-weight change reaches the voter at the end of the account's proxy
   chain (`chain_tops`: first account without a proxy within 4 levels; none beyond). The
   account's own proxy is the one in force at the event; the chain above it is the current
   one. A proxy change moves the account's weight (current weight minus its own later
   changes) from the old chain's voter to the new one's.
3. **Ordering rule**: each voter's vote operations split the window into segments. A weight
   change counts for a witness only in the segments where the voter backed it (from
   `witness_votes_history` and `current_witness_votes`). A vote is valued at the voter's
   weight then: its weight now minus every change of it in later segments (including changes
   of its own VESTS made while it proxied them elsewhere).
4. Per witness and cause: `vests` and the distinct voters with a nonzero contribution; a
   `total` row per witness (sum of the causes, distinct voters across them).

Without approximations this telescopes to `votes now - votes at the window start`.
Two snapshots of steem-20 matched `witness_votes_cache.votes`' change to the VESTS for every
witness.

## Known approximations

- Chains above an account's own proxy are the current ones: an account joining or leaving a
  proxy mid-window can be attributed to the wrong voter for the time before the change.
- The weight a proxy change moves subtracts only the account's own later changes, not those
  of accounts proxying to it.
- A power-down is its full VESTS; when it also cancels delayed VESTS (power-up still in its
  30-day delay) the weight moves by less.

## Endpoint

`hafbe_backend.witness_votes_change_breakdown(INT[])` builds the JSON (see
[endpoints/witnesses.md](../endpoints/witnesses.md)). `rank_start` is computed on read:
`RANK()` by `votes - total` over the witnesses with a `witness_votes_cache` or `total` row;
any other witness shares the rank after every witness with more than zero.

## Testing

`tests/witness_votes_change_by_cause/run_test.sh` (see tests.md).
