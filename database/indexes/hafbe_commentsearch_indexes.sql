-- noqa: disable=LT02, PRS

--used in permlink search API, for filtering by 'all' and 'comment'
SELECT hive.register_index_dependency(
    'hafbe_app',
    $$
    CREATE INDEX IF NOT EXISTS hive_operations_comment_search_permlink ON hafd.operations USING btree
    (
        (body_binary::jsonb -> 'value' ->> 'author'),
        hafd.operation_id_to_block_num(id) DESC
    )
    WHERE hafd.operation_id_to_type_id(id) = 1
    $$
);

--used in permlink search API, for filtering by 'post'
SELECT hive.register_index_dependency(
    'hafbe_app',
    $$
    CREATE INDEX IF NOT EXISTS hive_operations_comment_search_permlink_parent_author ON hafd.operations USING btree
    (
        (body_binary::jsonb -> 'value' ->> 'author'),
        (body_binary::jsonb -> 'value' ->> 'parent_author'),
        hafd.operation_id_to_block_num(id) DESC
    )
    WHERE hafd.operation_id_to_type_id(id) = 1
    $$
);

SELECT hive.register_index_dependency(
    'hafbe_app',
    $$
    CREATE INDEX IF NOT EXISTS hive_operations_comment_search_permlink_author ON hafd.operations USING btree
    (
        (body_binary::jsonb -> 'value' ->> 'author'),
        (body_binary::jsonb -> 'value' ->> 'permlink')
    )
    WHERE hafd.operation_id_to_type_id(id) IN (0, 1, 17, 19, 51, 52, 53, 61, 63, 72, 73)
    $$
);

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
