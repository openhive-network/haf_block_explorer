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
| `virtual_supply` | Virtual supply in milli-HIVE as a JSON string |
| `debt_ratio_pct` | Provisional issue formula rounded to three decimal places; numeric or null for zero virtual supply |
| `hbd_interest_rate` | Declared rate in basis points: `1500` means 15% |

**The formula is provisional pending clarification in issue #147:**
`100 * current_hbd_supply / virtual_supply`. It compares amounts in different
asset units and must not be interpreted as the protocol debt ratio. The SQL
uses `NUMERIC`, rounds the result to three decimal places and returns null for a zero denominator.
Both supply fields preserve the full integer amount as text to avoid precision loss in JSON clients.
Responses have a two-second cache lifetime while this definition is provisional.

## Implementation

`hafbe_backend.get_aggregation_blocks()` returns `date` and `last_block_num` for
the requested granularity, block range and direction. It reads existing daily or
monthly transaction statistics; weekly periods select the last daily block and
yearly periods select the last monthly block. Missing periods look up the last
available block before the next period starts, bounded by the processed head.

The endpoint joins these numbers to `hafbe_app.blocks_view`, so supplies and rate
come from the same block and the same application fork. The period label can be
later than that block when synchronization is behind. Empty processed history
returns an empty array. There are no new tables, state processors or backfill.

## Tests

Tavern requests live in `tests/tavern/patterns-mainnet/get_hbd_status/`.
Their `.pat.json` files originate from CI job `3270133` on the 5M-block mainnet
fixture. Positive patterns reflect the supply strings and the debt ratio rounded
to three decimal places; negative patterns preserve the validation errors.
