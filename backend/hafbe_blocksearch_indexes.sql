SET ROLE hafbe_owner;
  
  CREATE INDEX IF NOT EXISTS hive_operations_permlink_author_test ON hive.operations USING btree
  (
	jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
	jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink')
  )
  WHERE op_type_id = 1;

  CREATE INDEX IF NOT EXISTS hive_operations_reversible_permlink_author_test ON hive.operations_reversible USING btree
  (
	jsonb_extract_path_text(body_binary::jsonb, 'value', 'author'),
	jsonb_extract_path_text(body_binary::jsonb, 'value', 'permlink')
  )
  WHERE op_type_id = 1;


RESET ROLE;