CREATE EXTENSION IF NOT EXISTS pg_trgm;

SET ROLE hafbe_owner;

CREATE INDEX IF NOT EXISTS hive_operations_comment_author_permlink ON hive.operations USING gin
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'author') gin_trgm_ops,
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink') gin_trgm_ops,
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'parent_author') gin_trgm_ops,
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'parent_permlink') gin_trgm_ops
)
WHERE op_type_id = 1;

CREATE INDEX IF NOT EXISTS hive_operations_vote_author_permlink ON hive.operations USING gin
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'author') gin_trgm_ops,
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink') gin_trgm_ops,
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'voter') gin_trgm_ops,
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'weight') gin_trgm_ops
)
WHERE op_type_id = ANY(ARRAY[0,72]);

CREATE INDEX IF NOT EXISTS hive_operations_delete_comment_author_permlink ON hive.operations USING gin
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'author') gin_trgm_ops,
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink') gin_trgm_ops
)
WHERE op_type_id = ANY(ARRAY[17,73]);


CREATE INDEX IF NOT EXISTS hive_operations_comment_options_author_permlink ON hive.operations USING gin
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'author') gin_trgm_ops,
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink') gin_trgm_ops
)
WHERE op_type_id = 19;

CREATE INDEX IF NOT EXISTS hive_operations_author_reward_author_permlink ON hive.operations USING gin
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'author') gin_trgm_ops,
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink') gin_trgm_ops
)
WHERE op_type_id = 51;

CREATE INDEX IF NOT EXISTS hive_operations_comment_benefactor_author_permlink ON hive.operations USING gin
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'author') gin_trgm_ops,
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink') gin_trgm_ops
)
WHERE op_type_id = 63;

CREATE INDEX IF NOT EXISTS hive_operations_comment_payout_author_permlink ON hive.operations USING gin
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'author') gin_trgm_ops,
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink') gin_trgm_ops
)
WHERE op_type_id = 61;

CREATE INDEX IF NOT EXISTS hive_operations_comment_reward_author_permlink ON hive.operations USING gin
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'author') gin_trgm_ops,
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink') gin_trgm_ops
)
WHERE op_type_id = 53;

/*

CREATE INDEX IF NOT EXISTS hive_operations_author_permlink ON hive.operations USING gin
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'author') gin_trgm_ops,
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink') gin_trgm_ops
)


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


WHERE op_type_id + 1 IN (1,2,18,20,52,54,62,64,73,74);

*/

--SELECT * FROM hafbe_endpoints.get_operation_keys(44) creator permlink??
--SELECT * FROM hafbe_endpoints.get_operation_keys(47) creator permlink??
--SELECT * FROM hafbe_endpoints.get_operation_keys(52) comment_author, comment_permlink


RESET ROLE;