CREATE SCHEMA IF NOT EXISTS hafbe_exceptions AUTHORIZATION hafbe_owner;

SET ROLE hafbe_owner;

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

CREATE OR REPLACE FUNCTION hafbe_exceptions.raise_block_num_too_high_exception(_block_num NUMERIC, _head_block_num INT)
RETURNS VOID
LANGUAGE 'plpgsql' IMMUTABLE
AS
$$
BEGIN
  RAISE EXCEPTION 'Block_num ''%'' is higher than head block (%).', _block_num, _head_block_num;
END
$$;

CREATE OR REPLACE FUNCTION hafbe_exceptions.raise_unknown_hash_exception(_hash TEXT)
RETURNS VOID
LANGUAGE 'plpgsql' IMMUTABLE
AS
$$
BEGIN
  RAISE EXCEPTION 'Block or transaction hash ''%'' does not exist in database.', _hash;
END
$$;

RESET ROLE;
