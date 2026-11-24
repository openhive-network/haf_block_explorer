# Witness Vote Change by Cause

**Source**: `db/process_witness_votes_change_by_cause.sql`
**Functions**:
- `hafbe_app.refresh_witness_votes_change_by_cause_in_background()` (one check of the refresher session `scripts/process_blocks.sh` runs beside block processing, #211)
- `hafbe_app.process_witness_votes_change_by_cause(_block INT)` (the due test and the contained refresh, for the last processed LIVE block)
- `hafbe_app.process_witness_votes_change_by_cause()` (refresh at the context's block: CI's sync, `.aidev/run-checks.sh`; the first LIVE block refreshes through `(_block)`, having no state row)
- `hafbe_app.refresh_witness_votes_change_by_cause(_block INT)`
- `hafbe_app.votes_change_by_cause_of(_first_block INT)` (one window, one set-based pass, witnesses and proposals: `target_kind`, `target_id`)
- `hafbe_app.witness_votes_change_by_cause_of(_first_block INT)` (its witness rows)
- `hafbe_app.witness_votes_change_today_start(_block INT)`, `hafbe_app.witness_votes_change_week_start(_block INT)`
- `hafbe_app.witness_votes_change_by_cause_indexes_ready()`

**Tables**: `hafbe_app.witness_votes_change_by_cause (witness_id, time_window, cause, vests, voters)`,
`hafbe_app.witness_votes_change_by_cause_start (witness_id, time_window, votes, rank_start)`,
`hafbe_app.witness_votes_change_by_cause_state (as_of_block, today_first_block, week_first_block)`,
`hafbe_app.proposal_votes_change_by_cause (proposal_id, time_window, cause, vests, voters)`,
`hafbe_app.proposal_votes_change_by_cause_start (proposal_id, time_window, votes, funded_start, gap_start)`.
None is registered with HAF (like the witness vote caches). The state row covers both.

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

Not in block processing (#211): the refresh took ~5 s warm and ~2 min cold on mainnet, inside
the block processor's one long statement, where `statement_timeout` cannot bound it.
`scripts/process_blocks.sh` starts a refresher beside the driver or the legacy loop: one psql
session (`application_name=block_explorer_votes_by_cause`) holding the shared
`haf_block_explorer` lock, that every `VOTES_BY_CAUSE_CHECK_SECONDS` (10) runs
`BEGIN ISOLATION LEVEL REPEATABLE READ; CALL hafbe_app.refresh_witness_votes_change_by_cause_in_background(); COMMIT;`
under `statement_timeout = VOTES_BY_CAUSE_TIMEOUT` (5min). Not started for a run bounded by
`--stop-at-block`, nor with `VOTES_BY_CAUSE_CHECK_SECONDS=0`.

The check refuses outside REPEATABLE READ (one snapshot = one processed block: HAF sets
`current_block_num` in the transaction that processes the block), enters HAF's contexts gate,
and does nothing unless `witness_votes_cache_state.block_num` is the context's current block
(the caches the start votes come from hold it: not during MASSIVE_PROCESSING, a wait for HAF or
a fork's rewind). Then `process_witness_votes_change_by_cause(current block)` refreshes when
100 blocks have passed since `as_of_block`, when `witness_votes_change_today_start(_block)` is
not the state's `today_first_block` (the first block of a new UTC day, so `today` resets with
`votes_daily_change`), when there is no state row yet, or when `as_of_block` is above `_block`
(a fork reverted the blocks it was computed from). Not at `as_of_block` itself: a stalled chain
would refresh on every check.
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
| `power_down` | per `fill_vesting_withdraw` and account: the sum of its `account_balance_history` VESTS changes plus the delayed VESTS it took (`withdraw_delayed_vests`), when negative (see below) |
| `power_up` | `delayed_voting` operations (`votes`) |
| `producer_reward` / `claimed_reward` | `account_balance_history` VESTS changes of `producer_reward` / `claim_reward_balance` |
| `proxy` | proxy changes derived from `account_proxies_history` (see below), and the vote removals `account_witness_proxy` cascades |
| `expired` / `declined` | the vote removals of `expired_account_notification` / `declined_voting_rights`, and a proxy removal in a block with one of these operations for the same account (hived pushes `proxy_cleared` before them) |

A balance change is `balance` minus the account's previous row (same account and nai), so
`account_balance_history` is read by `(account, nai, block)` for the accounts whose weight can
reach a witness (current voters, proxy setters, and the window's vote and proxy accounts).

A power-down payout moves the withdrawer's weight by less than its VESTS when the account has
delayed VESTS: hived takes the payout from them first (`delayed_voting::update_votes`), and the
VESTS it takes never mature. The balance tracker records them per payout in
`withdraw_delayed_vests`, so the cause is each fill's VESTS change plus that. hived emits one
`fill_vesting_withdraw` per VESTS route, then one for the rest. A route back to the withdrawer
is a fill with two rows for it (withdrawal and deposit): its change is their sum, 0. A route
to another account credits the recipient delayed VESTS, so the recipient's positive change is
not a cause.

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
- An account that had votes and sets a proxy in the window: later events of accounts proxying
  to it reach its new chain top, while its removed votes are valued at its current weight, which
  already includes them; `proxy` is off by their sum.
- VESTS changes by other operations are not causes. On today's chain they do not move the
  weight directly (power-ups and routed withdrawals are delayed since HF24, rewards are
  claimed since HF19); in older history, such as CI's 5M-block chain, they did, and the
  totals miss them.

## Failures

The breakdown is a display cache. `process_witness_votes_change_by_cause(_block)` runs the
refresh in a subtransaction: any failure (an error, a statement timeout, a cancel by request) is
logged as a WARNING naming the block, the refresh is rolled back and the previous breakdown
stays. The failed block is kept in the session setting
`hafbe_app.witness_votes_change_by_cause_failed_block`, and no refresh is attempted until 100
blocks after it (or a fork takes the chain back below it), also when there is no state row yet,
it is ahead or the chain stalls at the failed block: a refresh that keeps failing (a timeout) is
not paid for on every check. A new refresher session forgets it. The NOTICE for missing balance
tracker indexes is raised once per session.

**Time limit:** the refresher's `statement_timeout`; each check is a top-level statement.
(PostgreSQL arms `statement_timeout` when a top-level statement starts, which is why the refresh
could not be bounded inside block processing.) Each refresh logs its duration: a NOTICE, or a
WARNING past 10 s.

## Proposals (#209)

A proposal's votes (`proposal_vote_stats_cache.total_votes`, hived's
`dhf_processor::calculate_votes`) are the governance weight of its approvers that have no proxy.
The same pass attributes the same voter events to proposals, with the same causes and ordering
rule, and the refresh writes `proposal_votes_change_by_cause` beside the witness table, for the
same `as_of_block`. Differences from witnesses:

- **Votes**: `proposal_votes_history`. hived accepts an `update_proposal_votes` that names a
  proposal the voter already approves (or does not) and `process_proposals` logs a row for each
  named proposal, so only a row that changes the pair's approval (from its previous row, also
  before the window) is a vote change. A removal by `expired_account_notification` /
  `declined_voting_rights` (`process_proposal_expired_account`) is `expired` / `declined`; by
  `remove_proposal`, `votes_removed`.
- **Proxy**: setting a proxy removes an account's witness votes (the cascade), but hived keeps its
  proposal votes and ignores them while the proxy is set. So a vote change of an account with a
  proxy at the time moves nothing, and a proxy set (clear) stops (starts) each proposal the account
  approves counting its weight, as `proxy` (or `expired` / `declined` in an expiry's block). A
  switch from one proxy to another changes nothing. The account's weight reaches proposals through
  its chain top, like witnesses.
- **Fan-out**: an account backs up to 30 witnesses, but any number of proposals (mainnet
  2026-11-24: 64,676 approvals by 7,160 voters over 335 proposals, up to 251 per voter). The
  feeders add every proposal voter (about 3.7k accounts that vote for no witness).
- **Funding line**: `proposal_votes_change_by_cause_start` holds each proposal's votes at each
  window's start (`total_votes - total`) and its place against the return proposal (id 0) then.
  hived pays the active proposals by `total_votes`, then `proposal_id`, from the top, and the
  return proposal takes the budget left (`dhf_processor::sort_by_votes`, `transfer_payments`):
  `funded_start` is votes above the return proposal's (a tie orders proposal 0 first, so one
  without votes is below it); `gap_start` is votes minus the return proposal's. Both are taken at
  the window's start: NULL for the return proposal, for a proposal that had ended by then, and
  when the return proposal had ended or is removed; a proposal not started yet gets them, as
  where it would stand. A proposal created in the window counts as having had no votes at its
  start. Whether the budget reaches a proposal above the line is not modelled.

## Endpoint

`hafbe_backend.witness_votes_change_breakdown(INT[])` builds the JSON (see
[endpoints/witnesses.md](../endpoints/witnesses.md)). `rank_start` is stored by the refresh in
`witness_votes_change_by_cause_start`: one row per current witness and window, ranked like
`rank` (`refresh_witness_rank_cache()`: `ROW_NUMBER()` over `current_witnesses` by votes, voters_num,
witness_id, all DESC) on the start values: `witness_votes_cache.votes - total`, and
`voters_num` minus the window's net approvals in `witness_votes_history` (as `voters_num_daily_change`
counts them), both for `as_of_block` (the refresher only refreshes once the caches hold that block).
A witness nothing moved and nothing passed has `rank_start = rank`. A witness without a row
(registered after `as_of_block`) gets its current `rank`.

`hafbe_backend.proposal_votes_change_breakdown(INT[])` builds the proposals' JSON, with
`funded_start` / `gap_start` from `proposal_votes_change_by_cause_start` in place of `rank_start`
(see [endpoints/proposals.md](../endpoints/proposals.md)), for `/proposals` and the proposal
objects of `/proposals/votes`.

## Testing

`tests/witness_votes_change_by_cause/run_test.sh` (see tests.md).
