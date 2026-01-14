-- noqa: disable=LT02, PRS

-- =============================================================================
-- HAF Index Dependencies for hafbe_app
-- =============================================================================

-- used by get_input_type (search for block_num by block's hash)
SELECT hive.register_index_dependency(
    'hafbe_app',
    'CREATE UNIQUE INDEX IF NOT EXISTS uq_blocks_hash ON hafd.blocks USING btree (hash)'
);

-- =============================================================================
-- Comment Search Indexes
-- =============================================================================

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

Operation type IDs reference:
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

-- =============================================================================
-- Block Search Indexes (DEPRECATED - left for potential future usage)
-- These indexes are no longer utilized in current deployments but are kept
-- here for reference in case they are needed in the future.
-- =============================================================================

/*

--FIXME indexes must be created concurrently
SELECT hive.register_index_dependency(
    'hafbe_app',
    $$
    CREATE INDEX IF NOT EXISTS hive_operations_vote_author_permlink ON hafd.operations USING btree
    (
        jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
        jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink')
    )
    WHERE hafd.operation_id_to_type_id(id) = 0
    $$
);

SELECT hive.register_index_dependency(
    'hafbe_app',
    $$
    CREATE INDEX IF NOT EXISTS hive_operations_comment_author_permlink ON hafd.operations USING btree
    (
        jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
        jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink')
    )
    WHERE hafd.operation_id_to_type_id(id) = 1
    $$
);

SELECT hive.register_index_dependency(
    'hafbe_app',
    $$
    CREATE INDEX IF NOT EXISTS hive_operations_comment_parent_author_permlink ON hafd.operations USING btree
    (
        jsonb_extract_path_text(body_binary::jsonb, 'value', 'parent_author'),
        jsonb_extract_path_text(body_binary::jsonb, 'value', 'parent_permlink')
    )
    WHERE hafd.operation_id_to_type_id(id) = 1
    $$
);

SELECT hive.register_index_dependency(
    'hafbe_app',
    $$
    CREATE INDEX IF NOT EXISTS hive_operations_delete_comment_author_permlink ON hafd.operations USING btree
    (
        jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
        jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink')
    )
    WHERE hafd.operation_id_to_type_id(id) IN (17, 73)
    $$
);

SELECT hive.register_index_dependency(
    'hafbe_app',
    $$
    CREATE INDEX IF NOT EXISTS hive_operations_comment_options_author_permlink ON hafd.operations USING btree
    (
        jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
        jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink')
    )
    WHERE hafd.operation_id_to_type_id(id) = 19
    $$
);

SELECT hive.register_index_dependency(
    'hafbe_app',
    $$
    CREATE INDEX IF NOT EXISTS hive_operations_author_reward_author_permlink ON hafd.operations USING btree
    (
        jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
        jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink')
    )
    WHERE hafd.operation_id_to_type_id(id) = 51
    $$
);

SELECT hive.register_index_dependency(
    'hafbe_app',
    $$
    CREATE INDEX IF NOT EXISTS hive_operations_curation_author_permlink ON hafd.operations USING btree
    (
        jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
        jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink')
    )
    WHERE hafd.operation_id_to_type_id(id) = 52
    $$
);

SELECT hive.register_index_dependency(
    'hafbe_app',
    $$
    CREATE INDEX IF NOT EXISTS hive_operations_comment_benefactor_author_permlink ON hafd.operations USING btree
    (
        jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
        jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink')
    )
    WHERE hafd.operation_id_to_type_id(id) = 63
    $$
);

SELECT hive.register_index_dependency(
    'hafbe_app',
    $$
    CREATE INDEX IF NOT EXISTS hive_operations_comment_payout_author_permlink ON hafd.operations USING btree
    (
        jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
        jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink')
    )
    WHERE hafd.operation_id_to_type_id(id) = 61
    $$
);

SELECT hive.register_index_dependency(
    'hafbe_app',
    $$
    CREATE INDEX IF NOT EXISTS hive_operations_comment_reward_author_permlink ON hafd.operations USING btree
    (
        jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
        jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink')
    )
    WHERE hafd.operation_id_to_type_id(id) = 53
    $$
);

SELECT hive.register_index_dependency(
    'hafbe_app',
    $$
    CREATE INDEX IF NOT EXISTS hive_operations_effective_vote_author_permlink ON hafd.operations USING btree
    (
        jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
        jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink')
    )
    WHERE hafd.operation_id_to_type_id(id) = 72
    $$
);

*/
