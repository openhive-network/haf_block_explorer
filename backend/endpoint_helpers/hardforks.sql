SET ROLE hafbe_owner;

/*
 * get_hardforks: every hardfork applied at or below _current_block, with the block
 * that applied it and that block's timestamp.
 *
 * HF1 onward come from HAF's public hive.applied_hardforks_view (irreversible and
 * reversible rows, current fork only), not the private hafd.applied_hardforks.
 * HF0 is the genesis protocol: no hardfork operation applies it, so it is reported
 * at block 1. That keeps the inverse lookup total - every block belongs to an era.
 *
 * The timestamp is looked up per row (LATERAL ... LIMIT 1), not joined, as the
 * context-view guidance in scripts/claude/endpoints.md requires.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.get_hardforks(_current_block INT)
RETURNS SETOF hafbe_backend.hardfork
LANGUAGE sql STABLE
AS
$$
  SELECT h.hardfork_num, h.block_num, b.created_at
  FROM (
    SELECT 0 AS hardfork_num, 1 AS block_num
    WHERE _current_block >= 1
    UNION ALL
    SELECT ah.hardfork_num::INT, ah.block_num
    FROM hive.applied_hardforks_view ah
    WHERE ah.block_num <= _current_block
  ) h
  LEFT JOIN LATERAL (
    SELECT bv.created_at
    FROM hafbe_app.blocks_view bv
    WHERE bv.num = h.block_num
    LIMIT 1
  ) b ON TRUE
  ORDER BY h.hardfork_num;
$$;

RESET ROLE;
