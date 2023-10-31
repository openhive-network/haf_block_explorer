CREATE EXTENSION IF NOT EXISTS pg_trgm;

SET ROLE hafbe_owner;


CREATE INDEX IF NOT EXISTS hive_operations_permlink_author_test ON hive.operations USING gin
(
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'author') gin_trgm_ops,
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink') gin_trgm_ops,
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'parent_author') gin_trgm_ops,
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'parent_permlink') gin_trgm_ops,
    jsonb_extract_path_text(body_binary::jsonb, 'value', 'title') gin_trgm_ops
)
WHERE op_type_id = 1;


RESET ROLE;