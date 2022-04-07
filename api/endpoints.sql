DROP SCHEMA IF EXISTS hafbe_endpoints CASCADE;

CREATE SCHEMA IF NOT EXISTS hafbe_endpoints;

CREATE FUNCTION hafbe_endpoints.get_input_type(_input TEXT)
RETURNS TEXT
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  IF _input IS NULL OR (SELECT name FROM hive.accounts WHERE name = _input) IS NOT NULL THEN
    RETURN 'account_name';
  ELSIF _input SIMILAR TO '([a-f0-9]{40})' THEN
    RETURN 'operation_hash';
  ELSIF _input SIMILAR TO '(\d+)' THEN
    RETURN 'block_num';
  ELSE
    RETURN 'block_hash';
  END IF;
END
$$
;

CREATE FUNCTION hafbe_endpoints.get_block_num(_block_hash BYTEA)
RETURNS INT
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  -- TODO: add single line query to return block num by hash to backend and call it here
  RETURN NULL;
END
$$
;

CREATE FUNCTION hafbe_endpoints.get_head_block_num()
RETURNS INT
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  -- TODO: add single line query to return last block from haf_block_log db
  RETURN 0;
END
$$
;

-- similar function is used in HAfAH repo's postgrest/hafah_api_v2.sql
CREATE FUNCTION hafbe_endpoints.get_account_history(_account VARCHAR, _start BIGINT = -1, _limit BIGINT = 1000, _operation_filter_low NUMERIC = 0, _operation_filter_high NUMERIC = 0, _include_reversible BOOLEAN = FALSE)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  -- hafah_python supports legacy style responses, but block explorer uses only new syle
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
  RETURN hafbe_backend.get_block(_block_num);
END
$$
;

CREATE FUNCTION hafbe_endpoints.get_transaction(_id TEXT, _include_reversible BOOLEAN = FALSE)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  -- TODO: add call to hafah_python schema function that returns transaction data, set __is_legacy_style to FALSE. Example: hafbe_endpoints.get_account_history()
  RETURN '{}';
END
$$
;

CREATE FUNCTION hafbe_endpoints.get_witnesses_by_vote()
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  -- TODO: add call to "condenser_api.get_witnesses_by_vote" as in hafbe_endpoints.get_block()
  RETURN '{}';
END
$$
;