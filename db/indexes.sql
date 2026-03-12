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

-- used in permlink search API, for filtering by 'all' and 'comment'
SELECT hive.register_index_dependency(
    'hafbe_app',
    $$
    CREATE INDEX IF NOT EXISTS hive_operations_comment_search_permlink ON hafd.operations USING btree
    (
        (body_value ->>'author'),
        hafd.operation_id_to_block_num(id) DESC
    )
    WHERE op_type_id = 1
    $$
);

-- used in permlink search API, for listing permlinks
SELECT hive.register_index_dependency(
    'hafbe_app',
    $$
    CREATE INDEX IF NOT EXISTS hive_operations_comment_search_permlink_parent_author ON hafd.operations USING btree
    (
        (body_value ->>'author'),
        (body_value ->>'parent_author'),
        hafd.operation_id_to_block_num(id) DESC
    )
    WHERE op_type_id = 1
    $$
);

-- used in permlink search API, for listing operations for a related permlink
SELECT hive.register_index_dependency(
    'hafbe_app',
    $$
    CREATE INDEX IF NOT EXISTS hive_operations_comment_search_permlink_author ON hafd.operations USING btree
    (
        (body_value ->>'author'),
        (body_value ->>'permlink')
    )
    WHERE op_type_id IN (0, 1, 17, 19, 51, 52, 53, 61, 63, 72, 73)
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
-- Block Search Indexes (Optional)
-- These indexes support block search functionality. They are created only when
-- custom.blocksearch_indexes is set to 'true' via install_app.sh --blocksearch-indexes=true
-- =============================================================================

DO $$
BEGIN
  IF current_setting('custom.blocksearch_indexes', true) = 'true' THEN
    RAISE NOTICE 'Creating block search indexes...';

    PERFORM hive.register_index_dependency(
      'hafbe_app',
      $idx$
      CREATE INDEX IF NOT EXISTS hive_operations_vote_author_permlink ON hafd.operations USING btree
      (
          jsonb_extract_path_text(body_value,'author'),
          jsonb_extract_path_text(body_value,'permlink')
      )
      WHERE op_type_id = 0
      $idx$
    );

    PERFORM hive.register_index_dependency(
      'hafbe_app',
      $idx$
      CREATE INDEX IF NOT EXISTS hive_operations_comment_author_permlink ON hafd.operations USING btree
      (
          jsonb_extract_path_text(body_value,'author'),
          jsonb_extract_path_text(body_value,'permlink')
      )
      WHERE op_type_id = 1
      $idx$
    );

    PERFORM hive.register_index_dependency(
      'hafbe_app',
      $idx$
      CREATE INDEX IF NOT EXISTS hive_operations_comment_parent_author_permlink ON hafd.operations USING btree
      (
          jsonb_extract_path_text(body_value,'parent_author'),
          jsonb_extract_path_text(body_value,'parent_permlink')
      )
      WHERE op_type_id = 1
      $idx$
    );

    PERFORM hive.register_index_dependency(
      'hafbe_app',
      $idx$
      CREATE INDEX IF NOT EXISTS hive_operations_delete_comment_author_permlink ON hafd.operations USING btree
      (
          jsonb_extract_path_text(body_value,'author'),
          jsonb_extract_path_text(body_value,'permlink')
      )
      WHERE op_type_id IN (17, 73)
      $idx$
    );

    PERFORM hive.register_index_dependency(
      'hafbe_app',
      $idx$
      CREATE INDEX IF NOT EXISTS hive_operations_comment_options_author_permlink ON hafd.operations USING btree
      (
          jsonb_extract_path_text(body_value,'author'),
          jsonb_extract_path_text(body_value,'permlink')
      )
      WHERE op_type_id = 19
      $idx$
    );

    PERFORM hive.register_index_dependency(
      'hafbe_app',
      $idx$
      CREATE INDEX IF NOT EXISTS hive_operations_author_reward_author_permlink ON hafd.operations USING btree
      (
          jsonb_extract_path_text(body_value,'author'),
          jsonb_extract_path_text(body_value,'permlink')
      )
      WHERE op_type_id = 51
      $idx$
    );

    PERFORM hive.register_index_dependency(
      'hafbe_app',
      $idx$
      CREATE INDEX IF NOT EXISTS hive_operations_curation_author_permlink ON hafd.operations USING btree
      (
          jsonb_extract_path_text(body_value,'author'),
          jsonb_extract_path_text(body_value,'permlink')
      )
      WHERE op_type_id = 52
      $idx$
    );

    PERFORM hive.register_index_dependency(
      'hafbe_app',
      $idx$
      CREATE INDEX IF NOT EXISTS hive_operations_comment_benefactor_author_permlink ON hafd.operations USING btree
      (
          jsonb_extract_path_text(body_value,'author'),
          jsonb_extract_path_text(body_value,'permlink')
      )
      WHERE op_type_id = 63
      $idx$
    );

    PERFORM hive.register_index_dependency(
      'hafbe_app',
      $idx$
      CREATE INDEX IF NOT EXISTS hive_operations_comment_payout_author_permlink ON hafd.operations USING btree
      (
          jsonb_extract_path_text(body_value,'author'),
          jsonb_extract_path_text(body_value,'permlink')
      )
      WHERE op_type_id = 61
      $idx$
    );

    PERFORM hive.register_index_dependency(
      'hafbe_app',
      $idx$
      CREATE INDEX IF NOT EXISTS hive_operations_comment_reward_author_permlink ON hafd.operations USING btree
      (
          jsonb_extract_path_text(body_value,'author'),
          jsonb_extract_path_text(body_value,'permlink')
      )
      WHERE op_type_id = 53
      $idx$
    );

    PERFORM hive.register_index_dependency(
      'hafbe_app',
      $idx$
      CREATE INDEX IF NOT EXISTS hive_operations_effective_vote_author_permlink ON hafd.operations USING btree
      (
          jsonb_extract_path_text(body_value,'author'),
          jsonb_extract_path_text(body_value,'permlink')
      )
      WHERE op_type_id = 72
      $idx$
    );

    RAISE NOTICE 'Block search indexes registered.';
  ELSE
    RAISE NOTICE 'Skipping block search indexes (custom.blocksearch_indexes is not set to true).';
  END IF;
END $$;
