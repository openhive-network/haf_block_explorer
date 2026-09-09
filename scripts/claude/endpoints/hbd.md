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
| `hbd_supply` | `current_hbd_supply` in milli-HBD, including treasury HBD |
| `virtual_supply` | Virtual supply in milli-HIVE |
| `debt_ratio_pct` | Provisional issue formula; numeric or null for zero virtual supply |
| `hbd_interest_rate` | Declared rate in basis points: `1500` means 15% |

**The formula is provisional pending clarification in issue #147:**
`100 * current_hbd_supply / virtual_supply`. It compares amounts in different
asset units and must not be interpreted as the protocol debt ratio. The SQL
uses `NUMERIC` without additional rounding and returns null for a zero denominator.
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

## MVP tests

Tavern requests live in `tests/tavern/patterns-mainnet/get_hbd_status/`.
Their `.pat.json` files are intentionally empty pending operator review. Expected
responses will be prepared afterwards using either a local HAF sync or CI output.
