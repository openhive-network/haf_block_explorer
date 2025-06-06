DROP SCHEMA IF EXISTS hafbe_indexes CASCADE;

CREATE SCHEMA IF NOT EXISTS hafbe_indexes AUTHORIZATION hafbe_owner;

SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_indexes.create_hafbe_indexes()
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
  CREATE INDEX IF NOT EXISTS current_witness_votes_witness_id ON hafbe_app.current_witness_votes USING btree (witness_id);
  
  --Can only vote once every 3 seconds, so sorting by block_num is sufficient
  CREATE INDEX IF NOT EXISTS witness_votes_history_witness_id_source_op ON hafbe_app.witness_votes_history USING btree (witness_id, source_op_block);

  CREATE INDEX IF NOT EXISTS account_proxies_history_account_id_source_op ON hafbe_app.account_proxies_history USING btree (account_id, source_op); 
  CREATE INDEX IF NOT EXISTS account_proxies_history_account_id ON hafbe_app.account_proxies_history USING btree (account_id);
  CREATE INDEX IF NOT EXISTS current_account_proxies_proxy_id ON hafbe_app.current_account_proxies USING btree (proxy_id);
  CREATE INDEX IF NOT EXISTS block_operations_block_num ON hafbe_app.block_operations USING btree (block_num);
  CREATE UNIQUE INDEX IF NOT EXISTS block_operations_op_type_id_block_num ON hafbe_app.block_operations USING btree (op_type_id, block_num);
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
