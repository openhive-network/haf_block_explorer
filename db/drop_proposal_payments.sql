SET ROLE hafbe_owner;

-- Installs made before current_proposals.paid_amount was updated directly kept
-- a proposal_payments ledger. Unregistering it drops its shadow table, triggers,
-- revert functions and hive_rowid; its vacuum requests are removed so hived
-- does not try to vacuum tables that no longer exist.
-- install_app.sh applies this after the operation parsers: until then the
-- previously installed process_proposal_pay_op still writes to the table.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM hafd.registered_tables
    WHERE origin_table_schema = 'hafbe_app' AND origin_table_name = 'proposal_payments'
  ) THEN
    PERFORM hive.app_unregister_table('hafbe_app', 'proposal_payments');
  END IF;

  DROP TABLE IF EXISTS hafbe_app.proposal_payments;

  IF to_regclass('hafd.vacuum_requests') IS NOT NULL THEN
    DELETE FROM hafd.vacuum_requests
    WHERE (schema_name, table_name) IN (
      ('hafbe_app', 'proposal_payments'),
      ('hafd', 'shadow_hafbe_app_proposal_payments')
    );
  END IF;
END
$$;

RESET ROLE;
