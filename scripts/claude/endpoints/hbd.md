# HBD Endpoint

`GET /hafbe-api/hbd/status` exposes `hafbe_endpoints.get_hbd_status`.
It returns a flat array without pagination, following transaction statistics.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `granularity` | `yearly` | `daily`, `weekly`, `monthly` or `yearly` |
| `direction` | `desc` | `asc` or `desc` |
| `from-block` | `NULL` | Block number or timestamp; defaults to genesis |
| `to-block` | `NULL` | Block number or timestamp; defaults to the processed head |

Explicit null parameters behave like omitted parameters. Block and timestamp
validation uses the same HAF conversion as transaction statistics. The containing
UTC periods are included in full; a range ending mid-month can therefore return
the final processed block of that month. Weeks start on Monday.

## Response

| Field | Meaning |
|-------|---------|
| `period` | End of the UTC period capped at current time, as in transaction statistics |
| `hbd_supply` | `current_hbd_supply` in milli-HBD, including treasury HBD, as a JSON string |
| `hive_supply` | `current_supply` in milli-HIVE at the sampled block, as a JSON string |
| `virtual_supply` | Virtual supply in milli-HIVE as a JSON string |
| `debt_ratio_gross_pct` | `100 * (virtual_supply - hive_supply) / virtual_supply`, rounded to three decimals; null for zero virtual supply |
| `debt_ratio_protocol_pct` | The ratio hived computes (`calculate_HBD_percent`), from the state after the sampled block (#153); see below |
| `hbd_interest_rate` | Declared rate in basis points: `1500` means 15% |

`virtual_supply - hive_supply` is the HBD supply valued in HIVE at the effective
median price (hard-cap adjustment included), so the gross share needs no feed lookup.

**Protocol ratio.** Before HF24 it equals the gross share. From HF24 (block from
`hafbe_app.applied_hardforks_view`, not a constant) hived leaves the treasury's
(`hive.fund`) **liquid** HBD out of the HBD supply and revalues the rest at the same
price: with `p = (virtual_supply - hive_supply) / hbd_supply` and
`h = max(hbd_supply - treasury_hbd, 0)` it is `100 * h*p / (h*p + hive_supply)`, and 0
when `h` is 0. The treasury's savings and reward HBD are not subtracted.
`hafbe_backend.hbd_protocol_debt_ratio_pct()` (`backend/endpoint_helpers/hbd.sql`) is the
formula, as a pure function. hived computes basis points during block processing,
slightly before the end-of-block state used here, so the two can differ by about one
basis point.

Which series the thresholds apply to:

| Era | Print-rate thresholds | Hard cap |
|-----|-----------------------|----------|
| before HF14 | none | none |
| HF14 to HF24 | gross (= protocol) | gross (= protocol) |
| HF24 to HF25 | protocol | gross |
| from HF25 | protocol | protocol |

Both supply fields preserve the full integer amount as text to avoid precision loss in
JSON clients. Fully processed, irreversible ranges are cached for a year, others for
two seconds; responses cached before a field was added keep their old shape until
they expire or are purged.

## Implementation

`hafbe_backend.get_aggregation_blocks()` returns `date` and `last_block_num` for
the requested granularity, block range and direction. It reads existing daily or
monthly transaction statistics; weekly periods select the last daily block and
yearly periods select the last monthly block. Missing periods look up the last
available block before the next period starts, bounded by the processed head.

The endpoint joins these numbers to `hafbe_app.blocks_view`, so supplies and rate
come from the same block and the same application fork. From HF24 it also reads the
treasury's liquid HBD at each sampled block from btracker's
`btracker_backend.account_balance_history_view` (`hive.fund`, HBD, the last change at
or before the block): one probe per period on the `(account, nai, block)` index. The period label can be
later than that block when synchronization is behind. Empty processed history
returns an empty array. There are no tables, state processors or backfill of its own.

## Tests

Tavern requests live in `tests/tavern/patterns-mainnet/get_hbd_status/`.
Their `.pat.json` files originate from CI job `3270133` on the 5M-block mainnet
fixture. Positive patterns reflect the supply strings and the ratios rounded to three
decimal places (the fixture ends before HF24, so the protocol ratio equals the gross
one there); negative patterns preserve the validation errors.

`tests/hbd_protocol_ratio/` (run by the `regression-test` job, rolled back) checks the
protocol formula against hived's integer basis-point computation on real mainnet
blocks and its edge cases, that every period of the pre-HF24 CI chain reports the
gross ratio, and the endpoint (daily and weekly) with HF24 and a `hive.fund` treasury
faked on sampled blocks of the CI chain.
