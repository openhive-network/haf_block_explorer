CREATE EXTENSION IF NOT EXISTS pg_trgm;

SET ROLE hafbe_owner;


CREATE INDEX IF NOT EXISTS hive_operations_parent_author_permlink ON hive.operations USING gin
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'parent_author') gin_trgm_ops,
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'parent_permlink') gin_trgm_ops
)
WHERE op_type_id = 1;

CREATE INDEX IF NOT EXISTS hive_operations_author_permlink ON hive.operations USING gin
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'author') gin_trgm_ops,
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink') gin_trgm_ops
)

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

WHERE op_type_id IN (0,1,17,19,51,53,61,63,72,73);



--SELECT * FROM hafbe_endpoints.get_operation_keys(44) creator permlink??
--SELECT * FROM hafbe_endpoints.get_operation_keys(47) creator permlink??
--SELECT * FROM hafbe_endpoints.get_operation_keys(52) comment_author, comment_permlink


RESET ROLE;