SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_backend.get_comment_history_operation_types(
    _operations TEXT
)
RETURNS INT []-- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
SET JIT = OFF
AS
$$
DECLARE
  _allowed_ids INT[]   := ARRAY[0, 1, 17, 19, 51, 52, 53, 61, 63, 72, 73];
  _operation_ids INT[] := (SELECT string_to_array(_operations, ',')::INT[]);
BEGIN
  IF _operations IS NULL THEN
    RETURN _allowed_ids;
  END IF;
  
  PERFORM hafah_backend.validate_operation_types(_operation_ids, _allowed_ids);

  RETURN _operation_ids;
END
$$;

RESET ROLE;
