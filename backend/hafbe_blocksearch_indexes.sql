CREATE EXTENSION IF NOT EXISTS btree_gin;

CREATE INDEX IF NOT EXISTS hive_operations_comment_author_permlink ON hive.operations USING gin
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink'),
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'parent_author'),
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'parent_permlink')
)
WHERE op_type_id = 1;

CREATE INDEX IF NOT EXISTS hive_operations_vote_author_permlink ON hive.operations USING gin
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink')
)
WHERE op_type_id = 0;

CREATE INDEX IF NOT EXISTS hive_operations_delete_comment_author_permlink ON hive.operations USING gin
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink')
)
WHERE op_type_id = any(ARRAY[17, 73]);


CREATE INDEX IF NOT EXISTS hive_operations_comment_options_author_permlink ON hive.operations USING gin
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink')
)
WHERE op_type_id = 19;

CREATE INDEX IF NOT EXISTS hive_operations_author_reward_author_permlink ON hive.operations USING gin
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink')
)
WHERE op_type_id = 51;

CREATE INDEX IF NOT EXISTS hive_operations_comment_benefactor_author_permlink ON hive.operations USING gin
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink')
)
WHERE op_type_id = 63;

CREATE INDEX IF NOT EXISTS hive_operations_comment_payout_author_permlink ON hive.operations USING gin
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink')
)
WHERE op_type_id = 61;

CREATE INDEX IF NOT EXISTS hive_operations_comment_reward_author_permlink ON hive.operations USING gin
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink')
)
WHERE op_type_id = 53;

CREATE INDEX IF NOT EXISTS hive_operations_effective_vote_author_permlink ON hive.operations USING gin
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink')
)
WHERE op_type_id = 72;

------------------------------------------


CREATE INDEX IF NOT EXISTS hive_operations_comment_search_permlink_author ON hive.operations USING btree
(
    (body_binary::jsonb -> 'value' ->> 'author'),
    (body_binary::jsonb -> 'value' ->> 'permlink')
)
WHERE op_type_id IN (0, 1, 17, 19, 51, 53, 61, 63, 72, 73);

CREATE INDEX IF NOT EXISTS hive_operations_comment_search_curation_author_permlink ON hive.operations USING gin
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'comment_author'),
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'comment_permlink')
)
WHERE op_type_id = 52;

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
