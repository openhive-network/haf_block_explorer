SET ROLE hafbe_owner;

/*
determines the input type as one of 'account_name', 'block_num', 'transaction_hash', 'block_hash'
returns 'account_name_array' when incomplete account name is provided
raises exceptions:
  > 'raise_block_num_too_high_exception()'
  > 'raise_unknown_hash_exception()'
  > 'raise_unknown_input_exception()'
*/

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_input_type(_input TEXT)
RETURNS JSON
LANGUAGE 'plpgsql' STABLE
AS
$$
DECLARE
  __hash BYTEA;
  __block_num INT;
  __head_block_num INT;
  __accounts_array JSON;
BEGIN
  -- names in db are lowercase, no uppercase is used in hashes
  SELECT lower(_input) INTO _input;

  -- first, name existance is checked
  IF (SELECT 1 FROM hive.accounts_view WHERE name = _input LIMIT 1) IS NOT NULL THEN

    PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=31536000"}]', true);

    RETURN json_build_object(
      'input_type', 'account_name',
      'input_value', _input
    );
  END IF;

  -- second, positive digit and not name is assumed to be block number
  IF _input SIMILAR TO '(\d+)' THEN
    SELECT hafbe_endpoints.get_head_block_num() INTO __head_block_num;
    IF _input::NUMERIC > __head_block_num THEN

      PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

      RETURN hafbe_exceptions.raise_block_num_too_high_exception(_input::NUMERIC, __head_block_num);
    ELSE

      PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=31536000"}]', true);

      RETURN json_build_object(
        'input_type', 'block_num',
        'input_value', _input
      );
    END IF;
  END IF;

  -- third, if input is 40 char hash, it is validated for transaction or block hash
  -- hash is unknown if failed to validate
  IF _input SIMILAR TO '([a-f0-9]{40})' THEN
    SELECT ('\x' || _input)::BYTEA INTO __hash;
    
    IF (SELECT trx_hash FROM hive.transactions_view WHERE trx_hash = __hash LIMIT 1) IS NOT NULL THEN

      PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=31536000"}]', true);

      RETURN json_build_object(
        'input_type', 'transaction_hash',
        'input_value', _input
      );
    ELSE
      SELECT bv.num 
      FROM hive.blocks_view bv
      WHERE bv.hash = __hash LIMIT 1 
      INTO __block_num;
    END IF;

    IF __block_num IS NOT NULL THEN

      PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=31536000"}]', true);

      RETURN json_build_object(
        'input_type', 'block_hash',
        'input_value', __block_num
      );
    ELSE

      PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

      RETURN hafbe_exceptions.raise_unknown_hash_exception(_input);
    END IF;
  END IF;

  -- fourth, it is still possible input is partial name, max 50 names returned.
  -- if no matching accounts were found, 'unknown_input' is returned
  SELECT btracker_app.find_matching_accounts(_input) INTO __accounts_array;
  IF __accounts_array IS NOT NULL THEN

    PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=31536000"}]', true);

    RETURN json_build_object(
      'input_type', 'account_name_array',
      'input_value', __accounts_array
    );
  ELSE

    PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

    RETURN json_build_object(
        'input_type', 'invalid_input',
        'input_value', _input
      );
  END IF;
END
$$;

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_hafbe_version()
RETURNS TEXT -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN

--100000s because version of hafbe doesn't change as often, but it may change
PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=100000"}]', true);

RETURN (
	SELECT git_hash
	FROM hafbe_app.version
);

END
$$;

RESET ROLE;
