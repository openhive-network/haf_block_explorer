--  \ \    / /_\ | _ \ \| |_ _| \| |/ __|
--   \ \/\/ / _ \|   / .` || || .` | (_ |
--    \_/\_/_/ \_\_|_\_|\_|___|_|\_|\___|
--
-- this file is only executed at startup if the function hafbe_indexes.do_haf_indexes_exist()
-- returns true.  This function has a list of the indexes created in this file, and returns
-- true if they all exist.  If you add, remove, or rename an index created in this file, you
-- must make a corresponding change in that function

CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS uq_hive_blocks_reversible_hash ON hive.blocks_reversible USING btree (hash, fork_id);
CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS uq_hive_blocks_hash ON hive.blocks USING btree (hash);
CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS uq_hive_blocks_reversible_created_at ON hive.blocks_reversible USING btree (created_at, fork_id);

--Indexes for comment_operation
CREATE INDEX CONCURRENTLY IF NOT EXISTS hive_operations_permlink_author ON hive.operations USING btree
(
    (body_binary::jsonb->'value'->>'author'),
    (body_binary::jsonb->'value'->>'permlink')
)
WHERE op_type_id = 1;

CREATE INDEX CONCURRENTLY IF NOT EXISTS hive_operations_reversible_permlink_author ON hive.operations_reversible USING btree
(
    (body_binary::jsonb->'value'->>'author'),
    (body_binary::jsonb->'value'->>'permlink')
)
WHERE op_type_id=1;

--Indexes for vote_operation
CREATE INDEX CONCURRENTLY IF NOT EXISTS hive_operations_voter ON hive.operations USING btree
(
    (body_binary::jsonb->'value'->>'voter')
)
WHERE op_type_id = 72;

CREATE INDEX CONCURRENTLY IF NOT EXISTS hive_operations_reversible_voter ON hive.operations_reversible USING btree
(
    (body_binary::jsonb->'value'->>'voter')
)
WHERE op_type_id = 72;

--Indexes for delete_comment_operation
CREATE INDEX CONCURRENTLY IF NOT EXISTS hive_operations_delete_permlink_author ON hive.operations USING btree
(
    (body_binary::jsonb->'value'->>'author'),
    (body_binary::jsonb->'value'->>'permlink')
)
WHERE op_type_id = 17;

CREATE INDEX CONCURRENTLY IF NOT EXISTS hive_operations_reversible_delete_permlink_author ON hive.operations_reversible USING btree
(
    (body_binary::jsonb->'value'->>'author'),
    (body_binary::jsonb->'value'->>'permlink')
)
WHERE op_type_id = 17;

--Indexes for pow_operation
CREATE INDEX CONCURRENTLY IF NOT EXISTS hive_operations_pow_operation ON hive.operations USING btree
(
    (body_binary::jsonb->'value'->>'worker_account')
)
WHERE op_type_id = 14;

CREATE INDEX CONCURRENTLY IF NOT EXISTS hive_operations_reversible_pow_operation ON hive.operations_reversible USING btree
(
    (body_binary::jsonb->'value'->>'worker_account')
)
WHERE op_type_id = 14;

--Indexes for pow2_operation
CREATE INDEX CONCURRENTLY IF NOT EXISTS hive_operations_pow2_operation ON hive.operations USING btree
(
    (body_binary::jsonb->'value'->'work'->'value'->'input'->>'worker_account')
)
WHERE op_type_id = 30;

CREATE INDEX CONCURRENTLY IF NOT EXISTS hive_operations_reversible_pow2_operation ON hive.operations_reversible USING btree
(
    (body_binary::jsonb->'value'->'work'->'value'->'input'->>'worker_account')
)
WHERE op_type_id = 30;

-- When you create expression indexes, you need to call ANALYZE to force postgresql to generate statistics on those expressions
ANALYZE VERBOSE hive.operations, hive.operations_reversible;
