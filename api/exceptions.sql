DROP SCHEMA IF EXISTS hafbe_exceptions CASCADE;

CREATE SCHEMA IF NOT EXISTS hafbe_exceptions;

CREATE FUNCTION hafbe_exceptions.raise_exception(_status INT, _error_id INT, _error TEXT, _message TEXT, _data TEXT = NULL)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  PERFORM set_config('response.status', _status::TEXT, TRUE);
  RETURN json_build_object(
      'status', _status,
      'error_id', _error_id,
      'error', _error,
      'message', _message,
      'data', _data
  );
END
$$
;

CREATE FUNCTION hafbe_exceptions.raise_block_num_too_high_exception(_block_num NUMERIC, _head_block_num INT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN hafbe_exceptions.raise_exception(406, 1, 'Not Acceptable',
    format('block_num ''%s'' is higher than head block (''%s'').', _block_num, _head_block_num)
  );
END
$$
;

CREATE FUNCTION hafbe_exceptions.raise_unknown_hash_exception(_hash TEXT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN hafbe_exceptions.raise_exception(404, 2, 'Not Found',
    format('Block or transaction hash ''%s'' does not exist in database.', _hash)
  );
END
$$
;

CREATE FUNCTION hafbe_exceptions.raise_unknown_input_exception(_input TEXT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN hafbe_exceptions.raise_exception(500, 3, 'Internal Server Error',
    'Type of received input is unknown.',
    format('Received input: ''%s''.', _input)
  );
END
$$
;

CREATE FUNCTION hafbe_exceptions.raise_unknown_block_hash_exception(_hash TEXT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN hafbe_exceptions.raise_exception(404, 4, 'Not Found',
    format('Block hash ''%s'' does not exist in database.', _hash)
  );
END
$$
;