SET ROLE hafbe_owner;

/*
 * get_hardforks: every hardfork applied at or below _current_block, with the block
 * that applied it and that block's timestamp.
 *
 * HF1 onward come from HAF's public hive.applied_hardforks_view, not the private
 * hafd.applied_hardforks. Its reversible rows follow HAF's head fork, not the
 * hafbe_app context's fork, so for the few seconds after a fork switch that hafbe
 * has not processed yet, a reversible hardfork row and the hafbe_app.blocks_view
 * timestamp can disagree. Only the 2-second responses can see that (irreversible
 * blocks agree), and a hardfork activates about once a year. HAF does not create
 * hafbe_app.applied_hardforks_view on 1.28.8; use it once it does.
 *
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

/*
 * get_hardfork_at_block: the hardfork in force at _block_num - the highest one
 * applied at or below it. Picks the row first and looks up ONE timestamp, rather
 * than probing hafbe_app.blocks_view for every earlier hardfork and discarding them.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.get_hardfork_at_block(_block_num INT)
RETURNS hafbe_backend.hardfork
LANGUAGE sql STABLE
AS
$$
  SELECT h.hardfork_num, h.block_num, b.created_at
  FROM (
    SELECT x.hardfork_num, x.block_num
    FROM (
      SELECT 0 AS hardfork_num, 1 AS block_num
      WHERE _block_num >= 1
      UNION ALL
      SELECT ah.hardfork_num::INT, ah.block_num
      FROM hive.applied_hardforks_view ah
      WHERE ah.block_num <= _block_num
    ) x
    ORDER BY x.hardfork_num DESC
    LIMIT 1
  ) h
  LEFT JOIN LATERAL (
    SELECT bv.created_at
    FROM hafbe_app.blocks_view bv
    WHERE bv.num = h.block_num
    LIMIT 1
  ) b ON TRUE;
$$;

RESET ROLE;
