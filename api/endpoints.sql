DROP SCHEMA IF EXISTS hafbe_endpoints CASCADE;

CREATE SCHEMA IF NOT EXISTS hafbe_endpoints;

-- determines the input type as one of 'account_name', 'block_num', 'transaction_hash', 'block_hash'
-- returns 'unknown_hash' or 'unknown_input' when incorrect input is provided
-- returns 'account_name_array' when incomplete account name is provided
CREATE FUNCTION hafbe_endpoints.get_input_type(_input TEXT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __input_type TEXT;
  __input_value TEXT = _input;
BEGIN
  -- first, name existance is checked
  IF (SELECT name FROM hive.accounts WHERE name = _input) IS NOT NULL THEN
    __input_type = 'account_name';

  -- second, positive digit and not name is assumed to be block number
  ELSIF _input SIMILAR TO '(\d+)' THEN
    __input_type = 'block_num';

  -- third, if input is 40 char hash, it is validated for transaction or block hash
  -- hash is unknown if failed to validate
  ELSIF _input SIMILAR TO '([a-f0-9]{40})' THEN
    IF (SELECT trx_hash FROM hive.transactions WHERE trx_hash = _input::BYTEA) IS NOT NULL THEN
      __input_type = 'transaction_hash';
    ELSIF (SELECT hash FROM hive.blocks WHERE hash = _input::BYTEA) IS NOT NULL THEN
      __input_type = 'block_hash';
      __input_value = hafbe_endpoints.get_block_num(_input);
    ELSE
      __input_type = 'unknown_hash';
    END IF;

  -- fourth, it is still possible input is partial name, max 50 names returned
  ELSE
    __input_value = json_build_object(
      'possible_accounts', (SELECT hafbe_endpoints.find_matching_accounts(_input::TEXT))
    );

    -- fifth, if no matching accounts were found, 'unknown_input' is returned
    IF (__input_value::JSON->>'possible_accounts') IS NULL THEN
      __input_type = 'unknown_input';
      __input_value = _input;
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
BEGIN
  RETURN hafbe_backend.get_block_num(_block_hash::BYTEA);
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

CREATE FUNCTION hafbe_endpoints.get_account_history(_account VARCHAR, _start BIGINT = -1, _limit BIGINT = 1000, _operation_filter_low NUMERIC = 0, _operation_filter_high NUMERIC = 0, _include_reversible BOOLEAN = FALSE)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __is_legacy_style BOOLEAN = FALSE;
BEGIN
  RETURN hafah_python.ah_get_account_history_json(_operation_filter_low, _operation_filter_high, _account, _start, _limit, _include_reversible, __is_legacy_style);
END
$$
;

CREATE FUNCTION hafbe_endpoints.get_block(_block_num INT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN hafbe_backend.get_block(_block_num::INT);
END
$$
;

CREATE FUNCTION hafbe_endpoints.get_transaction(_trx_hash BYTEA, _include_reversible BOOLEAN = FALSE, _is_legacy_style BOOLEAN = FALSE)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN hafah_python.get_transaction_json(_trx_hash, _include_reversible, _is_legacy_style);
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