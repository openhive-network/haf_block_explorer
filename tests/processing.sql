-- TODO Run these tests on a freshly created database

CREATE OR REPLACE PROCEDURE hafbe_app.test_process_witness_set_properties_operation()
LANGUAGE 'plpgsql'
AS
$BODY$
DECLARE
  op jsonb := '{"type":"witness_set_properties_operation","value":{"owner":"holger80","props":[["account_creation_fee","b80b00000000000003535445454d0000"],["key","0295a26f54381a6dba8eb5dc7536e57db267685f9386c714ead9be39a905364a88"]],"extensions":[]}}';
  op_view hafbe_views.witness_prop_op_view := ('witness', op::jsonb, op::hive.operation, 1, 42, now(), 1);
BEGIN
  PERFORM hive.process_operation(op_view, 'hafbe_app', 'update_current_witness');
END;
$BODY$
;

CALL hive.appproc_context_detach(ARRAY['hafbe_app', 'btracker_app']);
CALL hafbe_app.test_process_witness_set_properties_operation();
CALL hive.appproc_context_attach(ARRAY['hafbe_app', 'btracker_app'], 0);
