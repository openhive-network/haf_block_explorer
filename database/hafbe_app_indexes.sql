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
END
$$;

CREATE OR REPLACE FUNCTION hafbe_indexes.do_haf_indexes_exist()
RETURNS BOOLEAN
LANGUAGE 'plpgsql' VOLATILE
AS
$$
DECLARE __result BOOLEAN;
BEGIN
  select count(1) = 0 
  into __result
  from (values ('uq_hive_blocks_reversible_hash'),
               ('uq_hive_blocks_hash'),
               ('uq_hive_blocks_reversible_created_at'),
               ('hive_operations_permlink_author'),
               ('hive_operations_reversible_permlink_author'),
               ('hive_operations_voter'),
               ('hive_operations_reversible_voter'),
               ('hive_operations_delete_permlink_author'),
               ('hive_operations_reversible_delete_permlink_author'),
               ('hive_operations_pow_operation'),
               ('hive_operations_reversible_pow_operation'),
               ('hive_operations_pow2_operation'),
               ('hive_operations_reversible_pow2_operation'))
       desired_indexes(indexname)
  left join pg_indexes using (indexname)
  where pg_indexes.indexname is null;
  return __result;
END
$$;


RESET ROLE;
