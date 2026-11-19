-- The refresher session's check, refresh_witness_votes_change_by_cause_in_background()
-- (#211):
--   - block processing no longer refreshes the breakdown: single_processing() does not
--     call process_witness_votes_change_by_cause();
--   - outside a REPEATABLE READ transaction the check refuses;
--   - while the witness vote caches do not hold the context's current block (no LIVE
--     block processed it: the initial sync, a catch-up, a wait for HAF, a fork's
--     rewind) it refreshes nothing;
--   - once they do, it refreshes for that block, and a second check at the block
--     refreshes nothing.
--
-- Sets witness_votes_cache_state in a transaction, so the role must be a member of
-- hafbe_owner. Needs the balance tracker's indexes built and its schema first on the
-- search path. Everything is rolled back.

DO $$
BEGIN
  IF pg_get_functiondef('hafbe_app.single_processing(integer, boolean)'::regprocedure)
     LIKE '%process_witness_votes_change_by_cause%' THEN
    RAISE EXCEPTION 'single_processing() still refreshes the witness vote change by cause inside block processing';
  END IF;
  RAISE NOTICE 'single_processing(): no refresh of the witness vote change by cause';
END
$$;

DO $$
BEGIN
  BEGIN
    CALL hafbe_app.refresh_witness_votes_change_by_cause_in_background();
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE '%needs a REPEATABLE READ transaction%' THEN
      RAISE;
    END IF;
    RAISE NOTICE 'READ COMMITTED: refused (%)', SQLERRM;
    RETURN;
  END;
  RAISE EXCEPTION 'refresh_witness_votes_change_by_cause_in_background() ran in a READ COMMITTED transaction';
END
$$;

BEGIN ISOLATION LEVEL REPEATABLE READ;

CREATE FUNCTION pg_temp.expect_as_of_block(_case TEXT, _expected INT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  _as_of INT := (SELECT s.as_of_block FROM hafbe_app.witness_votes_change_by_cause_state s);
BEGIN
  IF _as_of IS DISTINCT FROM _expected THEN
    RAISE EXCEPTION '%: the breakdown is as of block %, expected %', _case, _as_of, _expected;
  END IF;
  RAISE NOTICE '%: as of block %', _case, _as_of;
END
$$;

SELECT c.current_block_num AS head FROM hafd.contexts c WHERE c.name = 'hafbe_app' \gset

SET ROLE hafbe_owner;
DELETE FROM hafbe_app.witness_votes_change_by_cause_state;
DELETE FROM hafbe_app.witness_votes_cache_state;
RESET ROLE;
CALL hafbe_app.refresh_witness_votes_change_by_cause_in_background();
SELECT pg_temp.expect_as_of_block('no witness vote cache state', NULL);

SET ROLE hafbe_owner;
INSERT INTO hafbe_app.witness_votes_cache_state (singleton, block_num) VALUES (TRUE, :head - 1);
RESET ROLE;
CALL hafbe_app.refresh_witness_votes_change_by_cause_in_background();
SELECT pg_temp.expect_as_of_block('the caches hold the block before the current one', NULL);

SET ROLE hafbe_owner;
UPDATE hafbe_app.witness_votes_cache_state SET block_num = :head;
RESET ROLE;
CALL hafbe_app.refresh_witness_votes_change_by_cause_in_background();
SELECT pg_temp.expect_as_of_block('the caches hold the current block', :head);

-- A second check at the same block: nothing is due, so nothing is written
SET ROLE hafbe_owner;
UPDATE hafbe_app.witness_votes_change_by_cause SET vests = vests + 1;
RESET ROLE;
SELECT set_config('test.bumped', COALESCE(sum(vests), 0)::TEXT, TRUE) FROM hafbe_app.witness_votes_change_by_cause;
CALL hafbe_app.refresh_witness_votes_change_by_cause_in_background();
SELECT pg_temp.expect_as_of_block('checked again at the current block', :head);
DO $$
BEGIN
  IF (SELECT COALESCE(sum(vests), 0) FROM hafbe_app.witness_votes_change_by_cause) <> current_setting('test.bumped')::NUMERIC THEN
    RAISE EXCEPTION 'a second check at the same block refreshed the breakdown again';
  END IF;
END
$$;

ROLLBACK;
