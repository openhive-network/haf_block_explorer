# Witness Vote Change by Cause

**Source**: `db/process_witness_votes_change_by_cause.sql`
**Functions**:
- `hafbe_app.process_witness_votes_change_by_cause(_block INT)` (LIVE, from `single_processing()`)
- `hafbe_app.process_witness_votes_change_by_cause()` (refresh at the context's block: CI's sync, `.aidev/run-checks.sh`; the first LIVE block refreshes through `(_block)`, having no state row)
- `hafbe_app.refresh_witness_votes_change_by_cause(_block INT)`
- `hafbe_app.witness_votes_change_by_cause_of(_first_block INT)` (one window, one set-based pass)
- `hafbe_app.witness_votes_change_today_start(_block INT)`, `hafbe_app.witness_votes_change_week_start(_block INT)`
- `hafbe_app.witness_votes_change_by_cause_indexes_ready()`

**Tables**: `hafbe_app.witness_votes_change_by_cause (witness_id, time_window, cause, vests, voters)`,
`hafbe_app.witness_votes_change_by_cause_start (witness_id, time_window, votes, rank_start)`,
`hafbe_app.witness_votes_change_by_cause_state (as_of_block, today_first_block, week_first_block)`.
None is registered with HAF (like the witness vote caches).

## Purpose

`votes_daily_change` counts only today's votes, at the voters' current weight. A witness's
`vests` also moves every block (producer rewards, claimed rewards) and with power-downs and
matured power-ups. This breaks each witness's change down by cause, over **today** (from the
first block at or after 00:00 UTC of `as_of_block`'s day, `witness_votes_change_today_start(_block)`:
the same window as `votes_daily_change`'s, `witness_votes_cache_window_start(_block)`, and like it
independent of the session's TimeZone) and **7d** (from the first block at or after `as_of_block`'s
time minus 7 days), for `votes_change_breakdown` on `/witnesses`. Neither window counts the block
before its boundary.

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
| `proxy` | proxy changes derived from `account_proxies_history` (see below), and the vote removals `account_witness_proxy` cascades |
| `expired` / `declined` | the vote removals of `expired_account_notification` / `declined_voting_rights`, and a proxy removal in a block with one of these operations for the same account (hived pushes `proxy_cleared` before them) |

A balance change is `balance` minus the account's previous row (same account and nai), so
`account_balance_history` is read by `(account, nai, block)` for the accounts whose weight can
reach a witness (current voters, proxy setters, and the window's vote and proxy accounts).

## How a pass works

1. **Events**: vote rows, proxy changes, own-weight changes (balance rows, `delayed_voting`).
   An account's proxy after each of its `account_proxies_history` rows is the one its last
   set (`proxy = TRUE`) named, unless a later row cleared that same proxy. A switch P→Q is
   written by `process_proxy_ops` as `(TRUE, Q)` then `(FALSE, P)`: hived pushes
   `proxy_cleared(P)` after the `account_witness_proxy`, so the clear of P is a no-op. The
   rows read are those of the accounts with a row in the window, from their last set before
   it (`account_proxies_history_source_op` finds the accounts); a proxy change is a row
   whose state differs from the previous one's.
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
- VESTS changes by other operations are not causes. On today's chain they do not move the
  weight directly (power-ups and routed withdrawals are delayed since HF24, rewards are
  claimed since HF19); in older history, such as CI's 5M-block chain, they did, and the
  totals miss them.

## Failures

The breakdown is a display cache. `process_witness_votes_change_by_cause(_block)` runs the
refresh in a subtransaction: any error, a statement timeout (`query_canceled`) included, is
logged as a WARNING naming the block, the refresh is rolled back and the previous breakdown
stays; the block is processed. The failed block is kept in the session setting
`hafbe_app.witness_votes_change_by_cause_failed_block`, and no refresh is attempted until 100
blocks after it (or a fork takes the chain back to it), also when there is no state row yet or
it is ahead: a refresh that keeps failing (a timeout) is not paid for on every block. A restart
forgets it, so the first due block after one tries again. The NOTICE for missing balance
tracker indexes is raised once per session.

## Endpoint

`hafbe_backend.witness_votes_change_breakdown(INT[])` builds the JSON (see
[endpoints/witnesses.md](../endpoints/witnesses.md)). `rank_start` is stored by the refresh in
`witness_votes_change_by_cause_start`: `RANK()` by `witness_votes_cache.votes - total` over
the witnesses with a cache or `total` row, both for `as_of_block` (`single_processing()`
refreshes the cache for the block first). A witness without a row there shares the rank after
every stored witness with more than zero.

## Testing

`tests/witness_votes_change_by_cause/run_test.sh` (see tests.md).
