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
  select not exists(select 1
                    from (values ('example_idx'))
                         desired_indexes(indexname)
                    left join pg_indexes using (indexname)
                    left join pg_class on desired_indexes.indexname = pg_class.relname
                    left join pg_index on pg_class.oid = indexrelid
                    where pg_indexes.indexname is null or not pg_index.indisvalid)
  into __result;
  return __result;
END
$$;
COMMENT ON FUNCTION hafbe_indexes.do_haf_indexes_exist() IS 'Returns true if all hafbe indexes created on core haf indexes exist and are valid';

RESET ROLE;
