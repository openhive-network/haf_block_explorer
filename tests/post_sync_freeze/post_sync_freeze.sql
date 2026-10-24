-- haf_block_explorer's visibility-map settings after its massive sync.
--
-- Checks that the insert-only and insert-mostly tables carry their autovacuum reloptions from
-- the install, and that hafbe_app.request_tables_freeze() queues one 'freeze' vacuum request for
-- every table registered in hafbe_app's context but the current_* ones, which the massive sync
-- VACUUM FULLs. Needs a HAF with vacuum request kinds (haf#360) and a role that may write
-- hafd.vacuum_requests (haf_admin).
-- Everything is rolled back.

BEGIN;

DO $$
DECLARE
  __table   TEXT;
  __options TEXT[];
BEGIN
  FOREACH __table IN ARRAY ARRAY[
    'block_operations', 'witness_votes_history', 'account_proxies_history', 'proposal_votes_history',
    'proposal_payments', 'transaction_stats_by_day', 'operation_type_stats_by_day',
    'wallet_stats_by_day', 'account_ops_count'
  ] LOOP
    SELECT reloptions INTO __options FROM pg_class WHERE oid = format('hafbe_app.%I', __table)::regclass;
    ASSERT __options @> ARRAY['autovacuum_vacuum_insert_scale_factor=0.005', 'autovacuum_freeze_min_age=0'],
      format('hafbe_app.%s has reloptions %s', __table, __options);
  END LOOP;

  SELECT reloptions INTO __options FROM pg_class WHERE oid = 'hafbe_app.account_ops_count'::regclass;
  ASSERT __options @> ARRAY['autovacuum_vacuum_scale_factor=0.01'],
    format('hafbe_app.account_ops_count has reloptions %s', __options);
END
$$;

DELETE FROM hafd.vacuum_requests WHERE schema_name = 'hafbe_app';
SELECT hafbe_app.request_tables_freeze();

-- Every table registered in the context, i.e. written during the sync, but the current_* tables.
DO $$
DECLARE
  __expected TEXT[] := (
    SELECT array_agg(origin_table_name ORDER BY origin_table_name)
    FROM hafd.registered_tables
    WHERE origin_table_schema = 'hafbe_app' AND origin_table_name NOT LIKE 'current\_%'
  );
  __requested TEXT[] := (
    SELECT array_agg(table_name ORDER BY table_name)
    FROM hafd.vacuum_requests
    WHERE schema_name = 'hafbe_app' AND kind = 'freeze' AND status = 'requested'
  );
BEGIN
  ASSERT __requested = __expected, format('freeze requests %s, expected %s', __requested, __expected);
  ASSERT NOT EXISTS (SELECT 1 FROM hafd.vacuum_requests WHERE schema_name = 'hafbe_app' AND kind <> 'freeze'),
    'request_tables_freeze() queued a vacuum request of another kind';
END
$$;

ROLLBACK;
