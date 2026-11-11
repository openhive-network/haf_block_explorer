SET ROLE hafbe_owner;

-- Installs made before current_proposals.total_budget existed get the column
-- here, NULL in every row. install_app.sh applies this right after
-- db/hafbe_app.sql, before the operation parsers: the new STEP A and
-- process_proposal_update_op write the column, while the previously installed
-- ones never name it, so the old code keeps working until it is replaced.
-- db/backfill_proposal_total_budget.sql fills the NULL rows once the new
-- processing functions are installed.
--
-- current_proposals is a registered table. HAF recreates its shadow table when a
-- column is added, and refuses the change while the shadow table still holds
-- rows (changes in blocks that are not irreversible yet). That refusal is
-- reported here with what to do about it.
DO $$
DECLARE
  __shadow_table TEXT;
  __pending      BOOLEAN := FALSE;
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'hafbe_app' AND table_name = 'current_proposals' AND column_name = 'total_budget'
  ) THEN
    RETURN;
  END IF;

  SELECT rt.shadow_table_name INTO __shadow_table
  FROM hafd.registered_tables rt
  WHERE rt.origin_table_schema = 'hafbe_app' AND rt.origin_table_name = 'current_proposals';

  IF __shadow_table IS NOT NULL THEN
    EXECUTE format('SELECT EXISTS (SELECT 1 FROM hafd.%I)', __shadow_table) INTO __pending;
  END IF;

  IF __pending THEN
    -- Only hafbe's own block processor clears these rows (as its blocks become
    -- irreversible), and it is stopped while the install holds the app lock.
    RAISE EXCEPTION 'hafbe_app.current_proposals has changes in blocks that are not irreversible yet, so HAF does not allow adding total_budget now. The column was not added. Start the previously installed hafbe block processor for a minute (until its last blocks are irreversible), stop it, and run the install again';
  END IF;

  ALTER TABLE hafbe_app.current_proposals ADD COLUMN total_budget NUMERIC NULL;
END
$$;

RESET ROLE;
