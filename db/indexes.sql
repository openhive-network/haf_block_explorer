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

  CREATE UNIQUE INDEX IF NOT EXISTS uq_hive_blocks_reversible_created_at ON hive.blocks_reversible USING btree (created_at, fork_id);
  CREATE UNIQUE INDEX IF NOT EXISTS uq_hive_blocks_created_at ON hive.blocks USING btree (created_at);
END
$$
;