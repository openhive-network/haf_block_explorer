-- =============================================================================
-- HAF state updates for the mock block range.
--
-- Detects the inserted mock block range (blocks numbered >= 91000000) and
-- configures hafd.hive_state + hafd.contexts so the hafbe_app processor will
-- pick up those blocks on its next iteration.
--
-- Mock range chosen to NOT collide with btracker's mocks (which use 90M+).
-- =============================================================================

SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_backend.get_mock_block_range()
RETURNS TABLE(min_block INT, max_block INT)
LANGUAGE plpgsql STABLE
AS $$
BEGIN
  -- Use a TIGHT window (not just `>= 91000000`) because real Hive has
  -- already passed 91M; a fully-synced DB would otherwise return real
  -- block numbers here and pollute the mock setup. The current fixture
  -- inserts blocks 91000001..91000006; the upper bound leaves headroom
  -- for adding more mock blocks without re-tuning this function.
  RETURN QUERY
  SELECT MIN(b.num)::INT, MAX(b.num)::INT
  FROM hafd.blocks b
  WHERE b.num BETWEEN 91000000 AND 91000099;
END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.update_irreversible_block()
RETURNS TABLE(start_block INT, end_block INT)
LANGUAGE plpgsql VOLATILE
AS $$
DECLARE
  _start INT;
  _end   INT;
BEGIN
  SELECT min_block, max_block INTO _start, _end
  FROM hafbe_backend.get_mock_block_range();

  IF _start IS NULL THEN
    RAISE EXCEPTION 'No mock blocks found in hafd.blocks (expected blocks >= 91000000)';
  END IF;

  UPDATE hafd.hive_state SET consistent_block = _end;

  -- Rewind both contexts to (start - 1) so app_next_iteration sees the
  -- mock range as the next batch to process. The fixtures only
  -- reference early-existing accounts (mirroring btracker's pattern —
  -- no hive.fund / steem.dao / other HF17+ accounts), so the full
  -- main-loop pipeline (btracker + state providers + hafbe) can run
  -- end-to-end without choking on a partial-sync HAF.
  --
  -- We update BOTH hafbe_app and hafbe_bal because hafbe_app's main
  -- loop requires the two contexts to stay synchronized — see the
  -- "Contexts {hafbe_app,hafbe_bal} are not synchronized" comment in
  -- db/hafbe_app.sql. This assumes a freshly-installed HAFBE+btracker —
  -- a partially-processed prior run leaves the contexts in divergent
  -- states this UPDATE cannot fix; the README's "Reset" section
  -- covers that path.
  UPDATE hafd.contexts
  SET current_block_num  = _start - 1,
      irreversible_block = _start - 1
  WHERE name IN ('hafbe_app', 'hafbe_bal');

  RETURN QUERY SELECT _start, _end;
END
$$;

RESET ROLE;
