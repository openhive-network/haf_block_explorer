DROP SCHEMA IF EXISTS hafbe_indexes CASCADE;

CREATE SCHEMA IF NOT EXISTS hafbe_indexes AUTHORIZATION hafbe_owner;

SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_indexes.create_hafbe_indexes()
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
  CREATE INDEX IF NOT EXISTS witness_votes_history_timestamp ON hafbe_app.witness_votes_history USING btree (timestamp);
  CREATE INDEX IF NOT EXISTS account_proxies_history_timestamp ON hafbe_app.account_proxies_history USING btree (timestamp); 
  CREATE INDEX IF NOT EXISTS account_proxies_history_account_id ON hafbe_app.account_proxies_history USING btree (account_id);

  ANALYZE VERBOSE;
END
$$;

CREATE OR REPLACE FUNCTION hafbe_indexes.create_btracker_indexes()
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
  CREATE INDEX IF NOT EXISTS idx_btracker_app_account_balance_history_nai ON btracker_app.account_balance_history(nai);
  CREATE INDEX IF NOT EXISTS idx_btracker_app_account_balance_history_account_nai ON btracker_app.account_balance_history(account, nai);
  
  ANALYZE VERBOSE;
END
$$;

CREATE OR REPLACE FUNCTION hafbe_indexes.create_haf_indexes()
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
  CREATE UNIQUE INDEX IF NOT EXISTS uq_hive_blocks_reversible_hash ON hive.blocks_reversible USING btree (hash, fork_id);
  CREATE UNIQUE INDEX IF NOT EXISTS uq_hive_blocks_hash ON hive.blocks USING btree (hash);

  --Indexes for comment_operation
  CREATE INDEX IF NOT EXISTS hive_operations_sync_permlink_author ON hive.operations USING btree
  (
	  (body_binary::jsonb->'value'->>'author'),
  	(body_binary::jsonb->'value'->>'permlink')
  )
  WHERE op_type_id = 1;
  
    CREATE INDEX IF NOT EXISTS hive_operations_sync_voter ON hive.operations USING btree
  (
  	(body_binary::jsonb->'value'->>'voter')
  )
  WHERE op_type_id = 72;

  --Indexes for delete_comment_operation
  CREATE INDEX IF NOT EXISTS hive_operations_sync_delete_permlink_author ON hive.operations USING btree
  (
	  (body_binary::jsonb->'value'->>'author'),
  	(body_binary::jsonb->'value'->>'permlink')
  )
  WHERE op_type_id = 17;

    --Indexes for pow_operation
  CREATE INDEX IF NOT EXISTS hive_operations_pow_operation ON hive.operations USING btree
  (
  	(body_binary::jsonb->'value'->>'worker_account')
  )
  WHERE op_type_id = 14;
  
    --Indexes for pow2_operation
  CREATE INDEX IF NOT EXISTS hive_operations_pow2_operation ON hive.operations USING btree
  (
  	(body_binary::jsonb->'value'->'work'->'value'->'input'->>'worker_account')
  )
  WHERE op_type_id = 30;


  ANALYZE VERBOSE;
END
$$;

RESET ROLE;
