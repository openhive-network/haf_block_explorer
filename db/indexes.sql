-- TODO: review if all indexes necessary
DROP SCHEMA IF EXISTS hafbe_indexes CASCADE;

CREATE SCHEMA IF NOT EXISTS hafbe_indexes AUTHORIZATION hafbe_owner;

CREATE FUNCTION hafbe_indexes.create_hafbe_indexes()
RETURNS VOID
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  CREATE INDEX IF NOT EXISTS current_witness_votes_voter_id ON hafbe_app.current_witness_votes USING btree (voter_id);
  CREATE INDEX IF NOT EXISTS witness_votes_history_timestamp ON hafbe_app.witness_votes_history USING btree (timestamp);
  CREATE INDEX IF NOT EXISTS account_proxies_history_timestamp ON hafbe_app.account_proxies_history USING btree (timestamp); 
  CREATE INDEX IF NOT EXISTS account_proxies_history_account_id ON hafbe_app.account_proxies_history USING btree (account_id);
  CREATE INDEX IF NOT EXISTS account_vests_account_id ON hafbe_app.account_vests USING btree (account_id);
END
$$
;

CREATE FUNCTION hafbe_indexes.create_haf_indexes()
RETURNS VOID
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  CREATE UNIQUE INDEX IF NOT EXISTS uq_hive_blocks_reversible_hash ON hive.blocks_reversible USING btree (hash, fork_id);
  CREATE UNIQUE INDEX IF NOT EXISTS uq_hive_blocks_hash ON hive.blocks USING btree (hash);

  CREATE INDEX IF NOT EXISTS hive_operations_reversible_timestamp_id ON hive.operations_reversible USING btree (timestamp, id, fork_id);
  CREATE INDEX IF NOT EXISTS hive_operations_timestamp_id ON hive.operations USING btree (timestamp, id);

  CREATE INDEX IF NOT EXISTS hive_operations_reversible_block_num_op_type_id ON hive.operations_reversible USING btree (block_num, op_type_id, fork_id);
  CREATE INDEX IF NOT EXISTS hive_operations_block_num_op_type_id ON hive.operations USING btree (block_num, op_type_id);

  CREATE INDEX IF NOT EXISTS hive_operations_reversible_timestamp ON hive.operations_reversible USING btree (timestamp, fork_id);
  CREATE INDEX IF NOT EXISTS hive_operations_timestamp ON hive.operations USING btree (timestamp);

  CREATE UNIQUE INDEX IF NOT EXISTS hive_account_operations_reversible_account_id_op_type_id_operation_id ON hive.account_operations_reversible USING btree (account_id, op_type_id, operation_id, fork_id);
  CREATE UNIQUE INDEX IF NOT EXISTS hive_account_operations_account_id_op_type_id_operation_id ON hive.account_operations USING btree (account_id, op_type_id, operation_id);

  CREATE INDEX IF NOT EXISTS hive_account_operations_reversible_block_num ON hive.account_operations_reversible USING btree (block_num, fork_id);
  CREATE INDEX IF NOT EXISTS hive_account_operations_block_num ON hive.account_operations USING btree (block_num);

  CREATE INDEX IF NOT EXISTS hive_account_operations_reversible_block_num_op_type_id ON hive.account_operations_reversible USING btree (block_num, op_type_id, fork_id);
  CREATE INDEX IF NOT EXISTS hive_account_operations_block_num_op_type_id ON hive.account_operations USING btree (block_num, op_type_id);

  CREATE INDEX IF NOT EXISTS hive_account_operations_reversible_operation_id_block_num ON hive.account_operations_reversible USING btree (operation_id, block_num, fork_id);
  CREATE INDEX IF NOT EXISTS hive_account_operations_operation_id_block_num ON hive.account_operations USING btree (operation_id, block_num);
END
$$
;