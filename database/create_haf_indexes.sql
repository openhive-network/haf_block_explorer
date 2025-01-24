-- noqa: disable=LT02, PRS

-- used by get_input_type (search for block_num by block's hash)
SELECT hive.register_index_dependency(
    'hafbe_app',
    $$
    CREATE UNIQUE INDEX IF NOT EXISTS uq_blocks_hash ON hafd.blocks USING btree (hash);
    $$
);
