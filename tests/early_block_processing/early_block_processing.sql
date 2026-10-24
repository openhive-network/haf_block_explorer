-- haf_block_explorer while hived replays with psql-massive-index-policy=keep-monotonic.
--
-- Sets hafd.indexes_constraints the way hive.disable_indexes_of_irreversible('keep-monotonic')
-- leaves it (the 'keep' core indexes created, the 'defer' ones missing) and checks that the
-- hafbe_app context group is delivered blocks then, that it is not with the drop-all policy,
-- and that finalize_account_ops_count waits for the hafd.account_operations indexes before it
-- reads the table. Needs a synced hafbe_app that is not forking yet, and a role that may update
-- hafd tables (haf_admin). Everything is rolled back.

BEGIN;

CREATE TEMPORARY TABLE early_group ON COMMIT DROP AS
SELECT contexts::hive.contexts_group AS contexts FROM hafd.applications
WHERE name = 'hafbe_app';

DO $$
DECLARE
  __contexts hive.contexts_group := (SELECT contexts FROM early_group);
BEGIN
  ASSERT __contexts IS NOT NULL, 'hafbe_app is not registered as an application';
  ASSERT NOT hive.app_is_forking('hafbe_app'), 'needs a hafbe_app that is still in its massive sync (not forking)';
  ASSERT (SELECT bool_and(early_block_processing) AND COUNT(*) = cardinality(__contexts)
          FROM hafd.contexts WHERE name = ANY(__contexts)),
    format('the install did not opt every context of %s in to early block processing', __contexts);

  -- drop-all: every core index is missing during the massive sync
  UPDATE hafd.indexes_constraints SET status = 'missing' WHERE contexts @> ARRAY[0];
  ASSERT NOT hive.is_instance_ready_for_contexts(__contexts), 'drop-all: the group must wait for the index restore';

  -- keep-monotonic
  UPDATE hafd.indexes_constraints
  SET status = CASE WHEN massive_sync_class = 'keep' THEN 'created' ELSE 'missing' END::hafd.index_status
  WHERE contexts @> ARRAY[0];
  ASSERT NOT hive.is_instance_ready(), 'keep-monotonic: the deferred indexes are missing, the instance must not be ready';
  ASSERT hive.is_instance_ready_for_contexts(__contexts), 'keep-monotonic: the group must be delivered blocks while hived replays';
  ASSERT NOT hive.are_core_indexes_created('hafd.account_operations'), 'keep-monotonic: hafd.account_operations indexes must be deferred';

  UPDATE hafd.contexts SET early_block_processing = FALSE WHERE name = __contexts[2];
  ASSERT NOT hive.is_instance_ready_for_contexts(__contexts), 'a group is early only when all its contexts opted in';
  UPDATE hafd.contexts SET early_block_processing = TRUE WHERE name = __contexts[2];
END
$$;

-- The deferred hafd.account_operations indexes are missing: the fill must wait for them, so it
-- is still waiting when the statement times out. run_test.sh checks HAF's "Waiting for core
-- indexes of hafd.account_operations" notice.
SET LOCAL statement_timeout = '5s';
DO $$
BEGIN
  PERFORM hafbe_app.finalize_account_ops_count(hive.app_get_current_block_num('hafbe_app'));
  RAISE EXCEPTION 'finalize_account_ops_count read hafd.account_operations before its indexes were restored';
EXCEPTION WHEN query_canceled THEN
  RAISE NOTICE 'finalize_account_ops_count was still waiting for hafd.account_operations at the timeout';
END
$$;
RESET statement_timeout;

-- Once hived restored them, the fill runs.
UPDATE hafd.indexes_constraints SET status = 'created'
WHERE contexts @> ARRAY[0] AND table_name = 'hafd.account_operations';
DELETE FROM hafbe_app.account_ops_count;
SELECT hafbe_app.finalize_account_ops_count(hive.app_get_current_block_num('hafbe_app'));
DO $$
BEGIN
  ASSERT EXISTS (SELECT 1 FROM hafbe_app.account_ops_count), 'finalize_account_ops_count filled nothing once the indexes exist';
END
$$;

ROLLBACK;
