DROP SCHEMA IF EXISTS hafbe_endpoints CASCADE;

CREATE SCHEMA IF NOT EXISTS hafbe_endpoints;

/*
determines the input type as one of 'account_name', 'block_num', 'transaction_hash', 'block_hash'
returns 'account_name_array' when incomplete account name is provided
raises exceptions:
  > 'raise_block_num_too_high_exception()'
  > 'raise_unknown_hash_exception()'
  > 'raise_unknown_input_exception()'
*/

CREATE FUNCTION hafbe_endpoints.get_input_type(_input TEXT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __input_type TEXT;
  __input_value TEXT = _input;
  __head_block_num INT;
BEGIN
  -- first, name existance is checked
  IF (SELECT name FROM hive.accounts WHERE name = _input) IS NOT NULL THEN
    __input_type = 'account_name';

  -- second, positive digit and not name is assumed to be block number
  ELSIF _input SIMILAR TO '(\d+)' THEN
    SELECT hafbe_endpoints.get_head_block_num() INTO __head_block_num;
    IF _input::NUMERIC > __head_block_num THEN
      RETURN hafbe_exceptions.raise_block_num_too_high_exception(_input::NUMERIC, __head_block_num);
    ELSE
      __input_type = 'block_num';
    END IF;

  -- third, if input is 40 char hash, it is validated for transaction or block hash
  -- hash is unknown if failed to validate
  ELSIF _input SIMILAR TO '([a-f0-9]{40})' THEN
    IF (SELECT trx_hash FROM hive.transactions WHERE trx_hash = _input::BYTEA) IS NOT NULL THEN
      __input_type = 'transaction_hash';
    ELSIF (SELECT hash FROM hive.blocks WHERE hash = _input::BYTEA) IS NOT NULL THEN
      __input_type = 'block_hash';
      __input_value = hafbe_endpoints.get_block_num(_input);
    ELSE
      RETURN hafbe_exceptions.raise_unknown_hash_exception(_input::TEXT);
    END IF;

  -- fourth, it is still possible input is partial name, max 50 names returned
  ELSE
    __input_value = json_build_object(
      'possible_accounts', (SELECT hafbe_endpoints.find_matching_accounts(_input::TEXT))
    );

    -- fifth, if no matching accounts were found, 'unknown_input' is returned
    IF (__input_value::JSON->>'possible_accounts') IS NULL THEN
      RETURN hafbe_exceptions.raise_unknown_input_exception(_input::TEXT);
    ELSE
      __input_type = 'account_name_array';
    END IF;
  END IF;

  RETURN json_build_object(
    'input_type', __input_type,
    'input_value', __input_value
  );
END
$$
;

CREATE FUNCTION hafbe_endpoints.get_block_num(_block_hash TEXT)
RETURNS INT
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __block_num INT = (SELECT hafbe_backend.get_block_num(_block_hash::BYTEA));
BEGIN
  IF __block_num IS NULL THEN
    RETURN hafbe_exceptions.raise_unknown_block_hash_exception(_block_hash);
  ELSE
    RETURN __block_num;
  END IF;
END
$$
;

CREATE FUNCTION hafbe_endpoints.find_matching_accounts(_partial_account_name TEXT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN btracker_app.find_matching_accounts(_partial_account_name);
END
$$
;

CREATE FUNCTION hafbe_endpoints.get_head_block_num()
RETURNS INT
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN hafbe_backend.get_head_block_num();
END
$$
;

CREATE FUNCTION hafbe_endpoints.get_operation_types()
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN hafbe_backend.get_operation_types();
END
$$
;

CREATE FUNCTION hafbe_endpoints.get_ops_by_account(_account VARCHAR, _start BIGINT = 9223372036854775807, _limit BIGINT = 1000, _filter SMALLINT[] = ARRAY[]::SMALLINT[], _head_block BIGINT = NULL)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  IF _start IS NULL OR _start < 0 THEN
    _start = 9223372036854775807;
  END IF;

  IF _limit IS NULL OR _limit <= 0 THEN
    _limit = 1000;
  END IF;

  IF _start < (_limit - 1) THEN
    RETURN hafbe_exceptions.raise_ops_limit_exception(_start, _limit);
  END IF;

  IF _head_block IS NULL THEN
    SELECT hafbe_endpoints.get_head_block_num() INTO _head_block;
  END IF;

  IF _filter IS NULL THEN
    _filter = ARRAY[]::SMALLINT[];
  END IF;

  RETURN hafbe_backend.get_ops_by_account(_account, _start, _limit, _filter, _head_block);
END
$$
;

CREATE FUNCTION hafbe_endpoints.get_block(_block_num INT, _filter SMALLINT[] = ARRAY[]::SMALLINT[])
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  IF _filter IS NULL THEN
    _filter = ARRAY[]::SMALLINT[];
  END IF;

  RETURN hafbe_backend.get_block(_block_num, _filter);
END
$$
;

CREATE FUNCTION hafbe_endpoints.get_transaction(_trx_hash BYTEA, _include_reversible BOOLEAN = FALSE)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __is_legacy_style BOOLEAN = FALSE;
BEGIN
  IF _include_reversible IS NULL THEN
    _include_reversible = FALSE;
  END IF;

  RETURN hafah_python.get_transaction_json(_trx_hash, _include_reversible, __is_legacy_style);
END
$$
;

CREATE FUNCTION hafbe_endpoints.get_witnesses_by_vote()
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN hafbe_backend.get_witnesses_by_vote();
END
$$
;