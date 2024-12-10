--  \ \    / /_\ | _ \ \| |_ _| \| |/ __|
--   \ \/\/ / _ \|   / .` || || .` | (_ |
--    \_/\_/_/ \_\_|_\_|\_|___|_|\_|\___|
--
-- this file is only executed at startup if the function hafbe_indexes.do_haf_indexes_exist()
-- returns true.  This function has a list of the indexes created in this file, and returns
-- true if they all exist.  If you add, remove, or rename an index created in this file, you
-- must make a corresponding change in that function
DO $$
  BEGIN
    IF EXISTS(SELECT 1 FROM pg_index WHERE NOT indisvalid AND indexrelid = (SELECT oid FROM pg_class WHERE relname = 'hive_operations_vote_author_permlink')) THEN
      RAISE NOTICE 'Dropping invalid index hive_operations_vote_author_permlink, it will be recreated';
      DROP INDEX hafd.hive_operations_vote_author_permlink;
    END IF;
  END
$$;
CREATE INDEX CONCURRENTLY IF NOT EXISTS hive_operations_vote_author_permlink ON hafd.operations USING btree 
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink')
)
WHERE hive.operation_id_to_type_id(id) = 0;

DO $$
  BEGIN
    IF EXISTS(SELECT 1 FROM pg_index WHERE NOT indisvalid AND indexrelid = (SELECT oid FROM pg_class WHERE relname = 'hive_operations_comment_author_permlink')) THEN
      RAISE NOTICE 'Dropping invalid index hive_operations_comment_author_permlink, it will be recreated';
      DROP INDEX hafd.hive_operations_comment_author_permlink;
    END IF;
  END
$$;
CREATE INDEX CONCURRENTLY IF NOT EXISTS hive_operations_comment_author_permlink ON hafd.operations USING btree
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink')
)
WHERE hive.operation_id_to_type_id(id) = 1;

DO $$
  BEGIN
    IF EXISTS(SELECT 1 FROM pg_index WHERE NOT indisvalid AND indexrelid = (SELECT oid FROM pg_class WHERE relname = 'hive_operations_comment_parent_author_permlink')) THEN
      RAISE NOTICE 'Dropping invalid index hive_operations_comment_parent_author_permlink, it will be recreated';
      DROP INDEX hafd.hive_operations_comment_parent_author_permlink;
    END IF;
  END
$$;
CREATE INDEX CONCURRENTLY IF NOT EXISTS hive_operations_comment_parent_author_permlink ON hafd.operations USING btree 
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'parent_author'),
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'parent_permlink')
)
WHERE hive.operation_id_to_type_id(id) = 1;

DO $$
  BEGIN
    IF EXISTS(SELECT 1 FROM pg_index WHERE NOT indisvalid AND indexrelid = (SELECT oid FROM pg_class WHERE relname = 'hive_operations_delete_comment_author_permlink')) THEN
      RAISE NOTICE 'Dropping invalid index hive_operations_delete_comment_author_permlink, it will be recreated';
      DROP INDEX hafd.hive_operations_delete_comment_author_permlink;
    END IF;
  END
$$;
CREATE INDEX CONCURRENTLY IF NOT EXISTS hive_operations_delete_comment_author_permlink ON hafd.operations USING btree 
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink')
)
WHERE hive.operation_id_to_type_id(id) IN (17, 73);

DO $$
  BEGIN
    IF EXISTS(SELECT 1 FROM pg_index WHERE NOT indisvalid AND indexrelid = (SELECT oid FROM pg_class WHERE relname = 'hive_operations_comment_options_author_permlink')) THEN
      RAISE NOTICE 'Dropping invalid index hive_operations_comment_options_author_permlink, it will be recreated';
      DROP INDEX hafd.hive_operations_comment_options_author_permlink;
    END IF;
  END
$$;
CREATE INDEX CONCURRENTLY IF NOT EXISTS hive_operations_comment_options_author_permlink ON hafd.operations USING btree 
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink')
)
WHERE hive.operation_id_to_type_id(id) = 19;

DO $$
  BEGIN
    IF EXISTS(SELECT 1 FROM pg_index WHERE NOT indisvalid AND indexrelid = (SELECT oid FROM pg_class WHERE relname = 'hive_operations_author_reward_author_permlink')) THEN
      RAISE NOTICE 'Dropping invalid index hive_operations_author_reward_author_permlink, it will be recreated';
      DROP INDEX hafd.hive_operations_author_reward_author_permlink;
    END IF;
  END
$$;
CREATE INDEX CONCURRENTLY IF NOT EXISTS hive_operations_author_reward_author_permlink ON hafd.operations USING btree 
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink')
)
WHERE hive.operation_id_to_type_id(id) = 51;

DO $$
  BEGIN
    IF EXISTS(SELECT 1 FROM pg_index WHERE NOT indisvalid AND indexrelid = (SELECT oid FROM pg_class WHERE relname = 'hive_operations_curation_author_permlink')) THEN
      RAISE NOTICE 'Dropping invalid index hive_operations_curation_author_permlink, it will be recreated';
      DROP INDEX hafd.hive_operations_curation_author_permlink;
    END IF;
  END
$$;
CREATE INDEX CONCURRENTLY IF NOT EXISTS hive_operations_curation_author_permlink ON hafd.operations USING btree 
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink')
)
WHERE hive.operation_id_to_type_id(id) = 52;

DO $$
  BEGIN
    IF EXISTS(SELECT 1 FROM pg_index WHERE NOT indisvalid AND indexrelid = (SELECT oid FROM pg_class WHERE relname = 'hive_operations_comment_benefactor_author_permlink')) THEN
      RAISE NOTICE 'Dropping invalid index hive_operations_comment_benefactor_author_permlink, it will be recreated';
      DROP INDEX hafd.hive_operations_comment_benefactor_author_permlink;
    END IF;
  END
$$;
CREATE INDEX CONCURRENTLY IF NOT EXISTS hive_operations_comment_benefactor_author_permlink ON hafd.operations USING btree 
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink')
)
WHERE hive.operation_id_to_type_id(id) = 63;

DO $$
  BEGIN
    IF EXISTS(SELECT 1 FROM pg_index WHERE NOT indisvalid AND indexrelid = (SELECT oid FROM pg_class WHERE relname = 'hive_operations_comment_payout_author_permlink')) THEN
      RAISE NOTICE 'Dropping invalid index hive_operations_comment_payout_author_permlink, it will be recreated';
      DROP INDEX hafd.hive_operations_comment_payout_author_permlink;
    END IF;
  END
$$;
CREATE INDEX CONCURRENTLY IF NOT EXISTS hive_operations_comment_payout_author_permlink ON hafd.operations USING btree 
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink')
)
WHERE hive.operation_id_to_type_id(id) = 61;

DO $$
  BEGIN
    IF EXISTS(SELECT 1 FROM pg_index WHERE NOT indisvalid AND indexrelid = (SELECT oid FROM pg_class WHERE relname = 'hive_operations_comment_reward_author_permlink')) THEN
      RAISE NOTICE 'Dropping invalid index hive_operations_comment_reward_author_permlink, it will be recreated';
      DROP INDEX hafd.hive_operations_comment_reward_author_permlink;
    END IF;
  END
$$;
CREATE INDEX CONCURRENTLY IF NOT EXISTS hive_operations_comment_reward_author_permlink ON hafd.operations USING btree 
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink')
)
WHERE hive.operation_id_to_type_id(id) = 53;

DO $$
  BEGIN
    IF EXISTS(SELECT 1 FROM pg_index WHERE NOT indisvalid AND indexrelid = (SELECT oid FROM pg_class WHERE relname = 'hive_operations_effective_vote_author_permlink')) THEN
      RAISE NOTICE 'Dropping invalid index hive_operations_effective_vote_author_permlink, it will be recreated';
      DROP INDEX hafd.hive_operations_effective_vote_author_permlink;
    END IF;
  END
$$;
CREATE INDEX CONCURRENTLY IF NOT EXISTS hive_operations_effective_vote_author_permlink ON hafd.operations USING btree 
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink')
)
WHERE hive.operation_id_to_type_id(id) = 72;

ANALYZE VERBOSE hafd.operations;
----------------------------------------------------------------------------------

/*

0	"hive::protocol::vote_operation"
1	"hive::protocol::comment_operation"
17	"hive::protocol::delete_comment_operation"
19	"hive::protocol::comment_options_operation"
51	"hive::protocol::author_reward_operation"
52	"hive::protocol::curation_reward_operation"
53	"hive::protocol::comment_reward_operation"
61	"hive::protocol::comment_payout_update_operation"
63	"hive::protocol::comment_benefactor_reward_operation"
72	"hive::protocol::effective_comment_vote_operation"
73	"hive::protocol::ineffective_delete_comment_operation"

*/
