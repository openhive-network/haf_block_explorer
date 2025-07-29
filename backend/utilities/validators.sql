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

RESET ROLE;
