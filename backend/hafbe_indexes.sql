--  \ \    / /_\ | _ \ \| |_ _| \| |/ __|
--   \ \/\/ / _ \|   / .` || || .` | (_ |
--    \_/\_/_/ \_\_|_\_|\_|___|_|\_|\___|
--
-- this file is only executed at startup if the function hafbe_indexes.do_haf_indexes_exist()
-- returns true.  This function has a list of the indexes created in this file, and returns
-- true if they all exist.  If you add, remove, or rename an index created in this file, you
-- must make a corresponding change in that function

-- noqa: disable=LT02

DO $$
  BEGIN
    IF EXISTS(SELECT 1 FROM pg_index WHERE NOT indisvalid AND indexrelid = (SELECT oid FROM pg_class WHERE relname = 'hive_operations_comment_search_permlink')) THEN
      RAISE NOTICE 'Dropping invalid index hive_operations_comment_search_permlink, it will be recreated';
      DROP INDEX hafd.hive_operations_comment_search_permlink;
    END IF;
  END
$$;
CREATE INDEX CONCURRENTLY IF NOT EXISTS hive_operations_comment_search_permlink ON hafd.operations USING btree
(
    (body_binary::jsonb -> 'value' ->> 'author'),
    (body_binary::jsonb -> 'value' ->> 'parent_author'),
	  (body_binary::jsonb -> 'value' ->> 'permlink'),
    hive.operation_id_to_block_num(id)
)
WHERE hive.operation_id_to_type_id(id) = 1;

DO $$
  BEGIN
    IF EXISTS(SELECT 1 FROM pg_index WHERE NOT indisvalid AND indexrelid = (SELECT oid FROM pg_class WHERE relname = 'hive_operations_comment_search_permlink_author')) THEN
      RAISE NOTICE 'Dropping invalid index hive_operations_comment_search_permlink_author, it will be recreated';
      DROP INDEX hafd.hive_operations_comment_search_permlink_author;
    END IF;
  END
$$;
CREATE INDEX CONCURRENTLY IF NOT EXISTS hive_operations_comment_search_permlink_author ON hafd.operations USING btree
(
    (body_binary::jsonb -> 'value' ->> 'author'),
    (body_binary::jsonb -> 'value' ->> 'permlink')
)
WHERE hive.operation_id_to_type_id(id) IN (0, 1, 17, 19, 51, 52, 53, 61, 63, 72, 73);

/*
DO $$
  BEGIN
    IF EXISTS(SELECT 1 FROM pg_index WHERE NOT indisvalid AND indexrelid = (SELECT oid FROM pg_class WHERE relname = 'hive_operations_vote_block_num')) THEN
      RAISE NOTICE 'Dropping invalid index hive_operations_vote_block_num, it will be recreated';
      DROP INDEX hafd.hive_operations_vote_block_num;
    END IF;
  END
$$;
CREATE INDEX CONCURRENTLY IF NOT EXISTS hive_operations_vote_block_num ON hafd.operations USING btree
(
  hive.operation_id_to_block_num(id)
)
WHERE hive.operation_id_to_type_id(id) = 0;

DO $$
  BEGIN
    IF EXISTS(SELECT 1 FROM pg_index WHERE NOT indisvalid AND indexrelid = (SELECT oid FROM pg_class WHERE relname = 'hive_operations_effective_vote_block_num')) THEN
      RAISE NOTICE 'Dropping invalid index hive_operations_effective_vote_block_num, it will be recreated';
      DROP INDEX hafd.hive_operations_effective_vote_block_num;
    END IF;
  END
$$;
CREATE INDEX CONCURRENTLY IF NOT EXISTS hive_operations_effective_vote_block_num ON hafd.operations USING btree
(
  hive.operation_id_to_block_num(id)
)
WHERE hive.operation_id_to_type_id(id) = 72;
*/

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
