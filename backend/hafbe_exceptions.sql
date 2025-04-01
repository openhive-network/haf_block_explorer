CREATE SCHEMA IF NOT EXISTS hafbe_exceptions AUTHORIZATION hafbe_owner;

SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_exceptions.raise_exception(
    _status INT, _error_id INT, _error TEXT, _message TEXT, _data TEXT = NULL
)
RETURNS JSON
LANGUAGE 'plpgsql' IMMUTABLE
AS
$$
BEGIN
  PERFORM set_config('response.status', _status::TEXT, TRUE);
  RETURN json_build_object(
      'status', _status,
      'error_id', _error_id,
      'error_type', _error,
      'message', _message,
      'data', _data
  );
END
$$;

CREATE OR REPLACE FUNCTION hafbe_exceptions.raise_block_num_too_high_exception(_block_num NUMERIC, _head_block_num INT)
RETURNS JSON
LANGUAGE 'plpgsql' IMMUTABLE
AS
$$
BEGIN
  RETURN hafbe_exceptions.raise_exception(406, 1, 'Not Acceptable',
    format('block_num ''%s'' is higher than head block (%s).', _block_num, _head_block_num)
  );
END
$$;

CREATE OR REPLACE FUNCTION hafbe_exceptions.raise_unknown_hash_exception(_hash TEXT)
RETURNS JSON
LANGUAGE 'plpgsql' IMMUTABLE
AS
$$
BEGIN
  RETURN hafbe_exceptions.raise_exception(404, 2, 'Not Found',
    format('Block or transaction hash ''%s'' does not exist in database.', _hash)
  );
END
$$;

CREATE OR REPLACE FUNCTION hafbe_exceptions.raise_unknown_input_exception(_input TEXT)
RETURNS JSON
LANGUAGE 'plpgsql' IMMUTABLE
AS
$$
BEGIN
  RETURN hafbe_exceptions.raise_exception(500, 3, 'Internal Server Error',
    'Type of received input is unknown.',
    format('Received input: ''%s''.', _input)
  );
END
$$;

CREATE OR REPLACE FUNCTION hafbe_exceptions.raise_ops_limit_exception(_start BIGINT, _limit BIGINT)
RETURNS JSON
LANGUAGE 'plpgsql' IMMUTABLE
AS
$$
BEGIN
  RETURN hafbe_exceptions.raise_exception(406, 4, 'Not Acceptable',
    'Start  is less than limit - 1',
    format('%s < %s - 1',  _start, _limit)
  );
END
$$;

CREATE OR REPLACE FUNCTION hafbe_exceptions.raise_no_such_column_exception(_order_by TEXT)
RETURNS JSON
LANGUAGE 'plpgsql' IMMUTABLE
AS
$$
BEGIN
  RETURN hafbe_exceptions.raise_exception(406, 5, 'Not Acceptable',
    'Provided ''_order_by'' column does not exist',
    format('''%s'' not in (account, vests, account_vests, proxied_vests, timestamp)',  _order_by)
  );
END
$$;

CREATE OR REPLACE FUNCTION hafbe_exceptions.raise_no_such_order_exception(_order_is TEXT)
RETURNS JSON
LANGUAGE 'plpgsql' IMMUTABLE
AS
$$
BEGIN
  RETURN hafbe_exceptions.raise_exception(406, 6, 'Not Acceptable',
    'Provided ''_order_is'' does not exist',
    format('''%s'' is not ''asc'' or ''desc''',  _order_is)
  );
END
$$;

CREATE OR REPLACE FUNCTION hafbe_exceptions.validate_limit(given_limit BIGINT, expected_limit INT,given_limit_name TEXT DEFAULT 'page-size')
RETURNS VOID -- noqa: LT01, CP05
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
BEGIN
  IF given_limit > expected_limit THEN
    RAISE EXCEPTION '% <= %: % of % is greater than maxmimum allowed', given_limit_name, expected_limit, given_limit_name, given_limit;
  END IF;

  RETURN;
END
$$;

CREATE OR REPLACE FUNCTION hafbe_exceptions.validate_page(given_page BIGINT, max_page INT)
RETURNS VOID -- noqa: LT01, CP05
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
BEGIN
  IF given_page > max_page AND given_page != 1 THEN
    RAISE EXCEPTION 'page <= %: page of % is greater than maxmimum page', max_page, given_page;
  END IF;

  RETURN;
END
$$;


CREATE OR REPLACE FUNCTION hafbe_exceptions.validate_negative_limit(given_limit BIGINT, given_limit_name TEXT DEFAULT 'page-size')
RETURNS VOID -- noqa: LT01, CP05
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
BEGIN
  IF given_limit <= 0 THEN
    RAISE EXCEPTION '% <= 0: % of % is lesser or equal 0', given_limit_name, given_limit_name, given_limit;
  END IF;

  RETURN;
END
$$;

CREATE OR REPLACE FUNCTION hafbe_exceptions.validate_negative_page(given_page BIGINT)
RETURNS VOID -- noqa: LT01, CP05
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
BEGIN
  IF given_page <= 0 THEN
    RAISE EXCEPTION 'page <= 0: page of % is lesser or equal 0', given_page;
  END IF;

  RETURN;
END
$$;

CREATE OR REPLACE FUNCTION hafbe_exceptions.rest_raise_missing_account(_account_name TEXT)
RETURNS VOID
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
BEGIN
  RAISE EXCEPTION 'Account ''%'' does not exist', _account_name;
END
$$;

RESET ROLE;
