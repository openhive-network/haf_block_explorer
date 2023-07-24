DROP SCHEMA IF EXISTS hafbe_indexes CASCADE;

CREATE SCHEMA IF NOT EXISTS hafbe_indexes AUTHORIZATION hafbe_owner;

SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_indexes.create_hafbe_indexes()
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
  CREATE INDEX IF NOT EXISTS current_witness_votes_voter_id ON hafbe_app.current_witness_votes USING btree (voter_id);
  CREATE INDEX IF NOT EXISTS witness_votes_history_timestamp ON hafbe_app.witness_votes_history USING btree (timestamp);
  CREATE INDEX IF NOT EXISTS account_proxies_history_timestamp ON hafbe_app.account_proxies_history USING btree (timestamp); 
  CREATE INDEX IF NOT EXISTS account_proxies_history_account_id ON hafbe_app.account_proxies_history USING btree (account_id);
  CREATE INDEX IF NOT EXISTS account_vests_account_id ON hafbe_app.account_vests USING btree (account_id);
  
  ANALYZE VERBOSE;
END
$$
;

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
$$
;

CREATE OR REPLACE FUNCTION hafbe_indexes.create_haf_indexes()
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
  CREATE UNIQUE INDEX IF NOT EXISTS uq_hive_blocks_reversible_hash ON hive.blocks_reversible USING btree (hash, fork_id);
  CREATE UNIQUE INDEX IF NOT EXISTS uq_hive_blocks_hash ON hive.blocks USING btree (hash);

  CREATE UNIQUE INDEX IF NOT EXISTS uq_hive_blocks_reversible_created_at ON hive.blocks_reversible USING btree (created_at, fork_id);
  CREATE UNIQUE INDEX IF NOT EXISTS uq_hive_blocks_created_at ON hive.blocks USING btree (created_at);

  --Indexes for comment_operation
  CREATE INDEX IF NOT EXISTS hive_operations_permlink_author ON hive.operations USING btree
  (
	  (body::jsonb->'value'->>'permlink'::TEXT),
	  (body::jsonb->'value'->>'author'::TEXT)
  )
  WHERE op_type_id = 1;
  
  CREATE INDEX IF NOT EXISTS hive_operations_reversible_permlink_author ON hive.operations_reversible USING btree
  (
    (body::jsonb->'value'->>'permlink'::TEXT), 
    (body::jsonb->'value'->>'author'::TEXT)
  )
  WHERE op_type_id=1;

  --Indexes for interest_operation
  CREATE INDEX IF NOT EXISTS hive_operations_is_saved_into_hbd_balance ON hive.operations USING btree
  (
  	((body::jsonb->'value'->>'is_saved_into_hbd_balance')::BOOLEAN)
  )
  WHERE op_type_id = 55;
  
  CREATE INDEX IF NOT EXISTS hive_operations_reversible_is_saved_into_hbd_balance ON hive.operations_reversible USING btree
  (
  	((body::jsonb->'value'->>'is_saved_into_hbd_balance')::BOOLEAN)
  )
  WHERE op_type_id = 55;
  
  --Indexes for reward_operations
    CREATE INDEX IF NOT EXISTS hive_operations_payout_must_be_claimed ON hive.operations USING btree
  (
  	((body::jsonb->'value'->>'payout_must_be_claimed')::BOOLEAN)
  )
  WHERE op_type_id in (51,63);
  
  CREATE INDEX IF NOT EXISTS hive_operations_reversible_payout_must_be_claimed ON hive.operations_reversible USING btree
  (
  	((body::jsonb->'value'->>'payout_must_be_claimed')::BOOLEAN)
  )
  WHERE op_type_id in (51,63);

  --Indexes for vote_operation
  CREATE INDEX IF NOT EXISTS hive_operations_voter ON hive.operations USING btree
  (
  	(body::jsonb->'value'->>'voter'::TEXT)
  )
  WHERE op_type_id = 72;
  
  CREATE INDEX IF NOT EXISTS hive_operations_reversible_voter ON hive.operations_reversible USING btree
  (
  	(body::jsonb->'value'->>'voter'::TEXT)
  )
  WHERE op_type_id = 72;

  ANALYZE VERBOSE;
END
$$
;

RESET ROLE;
