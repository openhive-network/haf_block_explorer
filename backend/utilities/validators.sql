SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_exceptions.validate_witness(_account_id INT, _account_name TEXT)
RETURNS VOID
LANGUAGE 'plpgsql'
STABLE
AS
$$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM hafbe_app.current_witnesses WHERE witness_id = _account_id) THEN
    PERFORM hafbe_exceptions.rest_raise_missing_witness(_account_name);
  END IF;
END
$$;

CREATE OR REPLACE FUNCTION hafbe_exceptions.validate_comment_search_indexes()
RETURNS VOID
LANGUAGE 'plpgsql'
STABLE
AS
$$
BEGIN
  IF NOT hafbe_app.isCommentSearchIndexesCreated() THEN
    RAISE EXCEPTION 'Comment search indexes are not installed';
  END IF;
END
$$;

CREATE OR REPLACE FUNCTION hafbe_exceptions.validate_block_search_indexes()
RETURNS VOID
LANGUAGE 'plpgsql'
STABLE
AS
$$
BEGIN
  IF NOT hafbe_app.isBlockSearchIndexesCreated() THEN
    RAISE EXCEPTION 'Block search indexes are not installed';
  END IF;
END
$$;

CREATE OR REPLACE FUNCTION hafbe_exceptions.validate_block_num_too_high(_first_block INT, _current_block INT)
RETURNS VOID
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
BEGIN
  IF _first_block IS NOT NULL AND _current_block < _first_block THEN
    PERFORM hafbe_exceptions.raise_block_num_too_high_exception(_first_block::NUMERIC, _current_block);
  END IF;
END
$$;

CREATE OR REPLACE FUNCTION hafbe_exceptions.validate_path_filter_keys(_operation_types INT[], _set_of_keys JSON)
RETURNS VOID
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
DECLARE 
  _is_key_incorrect BOOLEAN := FALSE;
  _invalid_key TEXT         := NULL;
BEGIN
  --check if provided keys are correct
  WITH user_provided_keys AS
  (
    SELECT json_array_elements_text(_set_of_keys) AS given_key
  ),
  haf_keys AS
  (
    SELECT json_array_elements_text(hafah_endpoints.get_operation_keys((SELECT unnest(_operation_types)))) AS keys
  ),
  check_if_given_keys_are_correct AS
  (
    SELECT up.given_key, hk.keys IS NULL AS incorrect_key
    FROM user_provided_keys up
    LEFT JOIN haf_keys hk ON replace(replace(hk.keys, ' ', ''),'\','') = replace(replace(up.given_key, ' ', ''),'\','')
  )
  SELECT given_key, incorrect_key INTO _invalid_key, _is_key_incorrect
  FROM check_if_given_keys_are_correct
  WHERE incorrect_key LIMIT 1;
  
  IF _is_key_incorrect THEN
    RAISE EXCEPTION 'Invalid key %', _invalid_key;
  END IF;
END
$$;

CREATE OR REPLACE FUNCTION hafbe_exceptions.validate_single_operation_type(_operation_types INT[])
RETURNS VOID
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
BEGIN
  IF array_length(_operation_types, 1) != 1 OR _operation_types IS NULL THEN 
    RAISE EXCEPTION 'Invalid set of operations, use single operation. ';
  END IF;
END
$$;

RESET ROLE;
