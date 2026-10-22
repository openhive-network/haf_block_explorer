# Hardfork Endpoints

| Endpoint | Function | Returns |
|----------|----------|---------|
| `GET /hafbe-api/hardforks` | `hafbe_endpoints.get_hardforks` | Every applied hardfork, ordered by number (flat array, no pagination) |
| `GET /hafbe-api/hardforks/{block-num}` | `hafbe_endpoints.get_hardfork_at_block` | The hardfork in force at that block (its protocol era) |

Both return `hafbe_backend.hardfork`:

| Field | Meaning |
|-------|---------|
| `hardfork_num` | Hardfork number; 0 is the genesis protocol |
| `block_num` | Block that applied the hardfork; 1 for hardfork 0 |
| `timestamp` | Production time (UTC) of that block |

## Rules

- **Source.** HF1 onward come from HAF's public `hive.applied_hardforks_view`, not
  the private `hafd.applied_hardforks`. Its `block_num` is `NOT NULL`, so no row is
  dropped. Its reversible rows follow HAF's head fork rather than the `hafbe_app`
  context's fork: for the seconds between a fork switch and hafbe processing it, a
  reversible hardfork row and its timestamp can disagree. Only 2-second responses can
  see it. HAF does not create `hafbe_app.applied_hardforks_view` on 1.28.8; switch to
  it once it does.
- **HF0.** HAF records no hardfork operation for the genesis protocol, so it is
  synthesised at block 1. This keeps the inverse lookup total: every block from 1
  up belongs to an era.
- **Bound.** Only hardforks at or below `get_hafbe_head_block()` are returned, so
  a node that is still syncing never reports a hardfork it has not processed.
- **Era of a block.** `/hardforks/{block-num}` returns the highest hardfork whose
  `block_num` is at or below the block. The activation block itself belongs to
  the new hardfork. `block-num` below 1 or above the processed head is a 400.
- **Timestamp.** The activation block's production time. It can be later than the
  scheduled time `database_api.get_hardfork_properties` reports, because a hardfork
  applies only once enough witnesses run it: HF24 was scheduled for 2020-10-06 14:00
  UTC and applied in block 47,797,680 at 2020-10-14 19:31:24 UTC. HF0 is listed at
  block 1 (16:05:00); hived gives the genesis time, 2016-03-24 16:00:00.
- **Caching.** The list keeps a 2-second lifetime: a new hardfork can appear at the
  head. The era of an irreversible block cannot change, so that lookup is cached
  for a year; a lookup above the irreversible block keeps 2 seconds.

## Implementation

`hafbe_backend.get_hardforks(_current_block)` (`backend/endpoint_helpers/hardforks.sql`)
builds the list and looks up each timestamp with a `LEFT JOIN LATERAL ... LIMIT 1`
on `hafbe_app.blocks_view`, per the context-view guidance in `endpoints.md`.
`hafbe_backend.get_hardfork_at_block(_block_num)` picks the highest hardfork at or
below the block first and then looks up that one timestamp. No tables, processing or backfill. On a synced node the full list takes
about 20 ms (29 rows).

## Tests

`tests/tavern/patterns-mainnet/get_hardforks/` and `.../get_hardfork_at_block/`.
The 5M-block mainnet fixture holds HF1 to HF13 (HF14 is at block 5,137,542), so the
list pattern has 14 rows. The inverse tests cover block 1, the last block before
HF1, the HF1 activation block, HF7 and HF8 one hour apart, and the head block; the
negative tests cover 0, a negative number, null and head + 1. `Cache-Control` is
asserted on the list (2 s) and on an irreversible lookup (1 year).

Not testable on this fixture: the 2-second branch of the lookup (every fixture
block is irreversible), the head bound on the list (HAF stops at 5M, below HF14),
reversible hardfork rows, and the nginx rewrites (Tavern calls `/rpc/*` directly).
