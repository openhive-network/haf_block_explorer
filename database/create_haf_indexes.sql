--  \ \    / /_\ | _ \ \| |_ _| \| |/ __|
--   \ \/\/ / _ \|   / .` || || .` | (_ |
--    \_/\_/_/ \_\_|_\_|\_|___|_|\_|\___|
--
-- this file is only executed at startup if the function hafbe_indexes.do_haf_indexes_exist()
-- returns true.  This function has a list of the indexes created in this file, and returns
-- true if they all exist.  If you add, remove, or rename an index created in this file, you
-- must make a corresponding change in that function
--
-- We do this because the ANALYZE at the end of this file is slow, and only needs to be run
-- if we actually created any indexes.  


-- Note, for each index below, we first check and see if it exists but is invalid; if so, we drop it.
-- That will cause it to be recreated by the subsequent CREATE IF NOT EXISTS
-- We could check/drop all of the indexes in a single DO block at the top of the file, which might
-- look cleaner.  But I figure this way, someone doing cut & paste is more likely to grab both the
-- drop and the create.
DO $$
  BEGIN
    IF EXISTS(SELECT 1 FROM pg_index WHERE NOT indisvalid AND indexrelid = (SELECT oid FROM pg_class WHERE relname = 'uq_hive_blocks_reversible_hash')) THEN
      RAISE NOTICE 'Dropping invalid index uq_hive_blocks_reversible_hash, it will be recreated';
      DROP INDEX IF EXISTS uq_hive_blocks_reversible_hash;
    END IF;
  END
$$;
CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS uq_hive_blocks_reversible_hash ON hive.blocks_reversible USING btree (hash, fork_id);

DO $$
  BEGIN
    IF EXISTS(SELECT 1 FROM pg_index WHERE NOT indisvalid AND indexrelid = (SELECT oid FROM pg_class WHERE relname = 'uq_hive_blocks_hash')) THEN
      RAISE NOTICE 'Dropping invalid index uq_hive_blocks_hash, it will be recreated';
      DROP INDEX IF EXISTS uq_hive_blocks_hash;
    END IF;
  END
$$;
CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS uq_hive_blocks_hash ON hive.blocks USING btree (hash);

DO $$
  BEGIN
    IF EXISTS(SELECT 1 FROM pg_index WHERE NOT indisvalid AND indexrelid = (SELECT oid FROM pg_class WHERE relname = 'uq_hive_blocks_reversible_created_at')) THEN
      RAISE NOTICE 'Dropping invalid index uq_hive_blocks_reversible_created_at, it will be recreated';
      DROP INDEX IF EXISTS uq_hive_blocks_reversible_created_at;
    END IF;
  END
$$;
CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS uq_hive_blocks_reversible_created_at ON hive.blocks_reversible USING btree (created_at, fork_id);

--Indexes for vote_operation
--Used in hafbe_app.process_block_range_data_c (counting votes)

DO $$
  BEGIN
    IF EXISTS(SELECT 1 FROM pg_index WHERE NOT indisvalid AND indexrelid = (SELECT oid FROM pg_class WHERE relname = 'hive_operations_voter')) THEN
      RAISE NOTICE 'Dropping invalid index hive_operations_voter, it will be recreated';
      DROP INDEX IF EXISTS hive_operations_voter;
    END IF;
  END
$$;
CREATE INDEX CONCURRENTLY IF NOT EXISTS hive_operations_voter ON hive.operations USING btree
(
    (body_binary::jsonb->'value'->>'voter')
)
WHERE op_type_id = 72;

DO $$
  BEGIN
    IF EXISTS(SELECT 1 FROM pg_index WHERE NOT indisvalid AND indexrelid = (SELECT oid FROM pg_class WHERE relname = 'hive_operations_reversible_voter')) THEN
      RAISE NOTICE 'Dropping invalid index hive_operations_reversible_voter, it will be recreated';
      DROP INDEX IF EXISTS hive_operations_reversible_voter;
    END IF;
  END
$$;
CREATE INDEX CONCURRENTLY IF NOT EXISTS hive_operations_reversible_voter ON hive.operations_reversible USING btree
(
    (body_binary::jsonb->'value'->>'voter')
)
WHERE op_type_id = 72;

--Indexes for pow_operation
--Used in hafbe_app.process_block_range_data_c (tracking mined parameter, account creation date)
DO $$
  BEGIN
    IF EXISTS(SELECT 1 FROM pg_index WHERE NOT indisvalid AND indexrelid = (SELECT oid FROM pg_class WHERE relname = 'hive_operations_pow_operation')) THEN
      RAISE NOTICE 'Dropping invalid index hive_operations_pow_operation, it will be recreated';
      DROP INDEX IF EXISTS hive_operations_pow_operation;
    END IF;
  END
$$;
CREATE INDEX CONCURRENTLY IF NOT EXISTS hive_operations_pow_operation ON hive.operations USING btree
(
    (body_binary::jsonb->'value'->>'worker_account')
)
WHERE op_type_id = 14;

DO $$
  BEGIN
    IF EXISTS(SELECT 1 FROM pg_index WHERE NOT indisvalid AND indexrelid = (SELECT oid FROM pg_class WHERE relname = 'hive_operations_reversible_pow_operation')) THEN
      RAISE NOTICE 'Dropping invalid index hive_operations_reversible_pow_operation, it will be recreated';
      DROP INDEX IF EXISTS hive_operations_reversible_pow_operation;
    END IF;
  END
$$;
CREATE INDEX CONCURRENTLY IF NOT EXISTS hive_operations_reversible_pow_operation ON hive.operations_reversible USING btree
(
    (body_binary::jsonb->'value'->>'worker_account')
)
WHERE op_type_id = 14;

--Indexes for pow2_operation
--Used in hafbe_app.process_block_range_data_c (tracking mined parameter, account creation date)
DO $$
  BEGIN
    IF EXISTS(SELECT 1 FROM pg_index WHERE NOT indisvalid AND indexrelid = (SELECT oid FROM pg_class WHERE relname = 'hive_operations_pow2_operation')) THEN
      RAISE NOTICE 'Dropping invalid index hive_operations_pow2_operation, it will be recreated';
      DROP INDEX IF EXISTS hive_operations_pow2_operation;
    END IF;
  END
$$;
CREATE INDEX CONCURRENTLY IF NOT EXISTS hive_operations_pow2_operation ON hive.operations USING btree
(
    (body_binary::jsonb->'value'->'work'->'value'->'input'->>'worker_account')
)
WHERE op_type_id = 30;

DO $$
  BEGIN
    IF EXISTS(SELECT 1 FROM pg_index WHERE NOT indisvalid AND indexrelid = (SELECT oid FROM pg_class WHERE relname = 'hive_operations_reversible_pow2_operation')) THEN
      RAISE NOTICE 'Dropping invalid index hive_operations_reversible_pow2_operation, it will be recreated';
      DROP INDEX IF EXISTS hive_operations_pow2_operation;
    END IF;
  END
$$;
CREATE INDEX CONCURRENTLY IF NOT EXISTS hive_operations_reversible_pow2_operation ON hive.operations_reversible USING btree
(
    (body_binary::jsonb->'value'->'work'->'value'->'input'->>'worker_account')
)
WHERE op_type_id = 30;

-- When you create expression indexes, you need to call ANALYZE to force postgresql to generate statistics on those expressions
ANALYZE VERBOSE hive.operations, hive.operations_reversible;
