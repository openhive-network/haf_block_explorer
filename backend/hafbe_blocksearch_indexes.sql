CREATE EXTENSION IF NOT EXISTS btree_gin;

-- Used in hafbe_backend.get_block_by_single_op and hafbe_backend.get_block_by_ops_group_by_block_num (endpoint hafbe_endpoints.get_block_by_op)
CREATE INDEX IF NOT EXISTS hive_operations_comment_author_permlink ON hive.operations USING gin
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink'),
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'parent_author'),
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'parent_permlink')
)
WHERE op_type_id = 1;

-- Used in hafbe_backend.get_block_by_single_op and hafbe_backend.get_block_by_ops_group_by_block_num (endpoint hafbe_endpoints.get_block_by_op)
CREATE INDEX IF NOT EXISTS hive_operations_vote_author_permlink ON hive.operations USING gin
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink')
)
WHERE op_type_id = 0;

-- Used in hafbe_backend.get_block_by_single_op and hafbe_backend.get_block_by_ops_group_by_block_num (endpoint hafbe_endpoints.get_block_by_op)
CREATE INDEX IF NOT EXISTS hive_operations_delete_comment_author_permlink ON hive.operations USING gin
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink')
)
WHERE op_type_id = any(ARRAY[17, 73]);

-- Used in hafbe_backend.get_block_by_single_op and hafbe_backend.get_block_by_ops_group_by_block_num (endpoint hafbe_endpoints.get_block_by_op)
CREATE INDEX IF NOT EXISTS hive_operations_comment_options_author_permlink ON hive.operations USING gin
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink')
)
WHERE op_type_id = 19;

-- Used in hafbe_backend.get_block_by_single_op and hafbe_backend.get_block_by_ops_group_by_block_num (endpoint hafbe_endpoints.get_block_by_op)
CREATE INDEX IF NOT EXISTS hive_operations_author_reward_author_permlink ON hive.operations USING gin
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink')
)
WHERE op_type_id = 51;

-- Used in hafbe_backend.get_block_by_single_op and hafbe_backend.get_block_by_ops_group_by_block_num (endpoint hafbe_endpoints.get_block_by_op)
CREATE INDEX IF NOT EXISTS hive_operations_comment_benefactor_author_permlink ON hive.operations USING gin
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink')
)
WHERE op_type_id = 63;

-- Used in hafbe_backend.get_block_by_single_op and hafbe_backend.get_block_by_ops_group_by_block_num (endpoint hafbe_endpoints.get_block_by_op)
CREATE INDEX IF NOT EXISTS hive_operations_comment_payout_author_permlink ON hive.operations USING gin
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink')
)
WHERE op_type_id = 61;

-- Used in hafbe_backend.get_block_by_single_op and hafbe_backend.get_block_by_ops_group_by_block_num (endpoint hafbe_endpoints.get_block_by_op)
CREATE INDEX IF NOT EXISTS hive_operations_comment_reward_author_permlink ON hive.operations USING gin
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink')
)
WHERE op_type_id = 53;

-- Used in hafbe_backend.get_block_by_single_op and hafbe_backend.get_block_by_ops_group_by_block_num (endpoint hafbe_endpoints.get_block_by_op)
CREATE INDEX IF NOT EXISTS hive_operations_effective_vote_author_permlink ON hive.operations USING gin
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink')
)
WHERE op_type_id = 72;

------------------------------------------

-- Used in hafbe_backend.get_comment_operations and hafbe_backend.get_comment_operations_count (endpoint hafbe_endpoints.get_comment_operations)
CREATE INDEX IF NOT EXISTS hive_operations_comment_search_permlink_author ON hive.operations USING btree
(
    (body_binary::jsonb -> 'value' ->> 'author'),
    (body_binary::jsonb -> 'value' ->> 'permlink')
)
WHERE op_type_id IN (0, 1, 17, 19, 51, 52, 53, 61, 63, 72, 73);

/*

0	"hive::protocol::vote_operation"
1	"hive::protocol::comment_operation"
17	"hive::protocol::delete_comment_operation"
19	"hive::protocol::comment_options_operation"
51	"hive::protocol::author_reward_operation"
53	"hive::protocol::comment_reward_operation"
61	"hive::protocol::comment_payout_update_operation"
63	"hive::protocol::comment_benefactor_reward_operation"
72	"hive::protocol::effective_comment_vote_operation"
73	"hive::protocol::ineffective_delete_comment_operation"

*/

--SELECT * FROM hafbe_endpoints.get_operation_keys(44) creator permlink??
--SELECT * FROM hafbe_endpoints.get_operation_keys(47) creator permlink??
--SELECT * FROM hafbe_endpoints.get_operation_keys(52) comment_author, comment_permlink
