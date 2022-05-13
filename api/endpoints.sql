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
  __block_num INT;
  __head_block_num INT;
  __accounts_array JSON;
BEGIN
  -- first, name existance is checked
  IF (SELECT name FROM hive.accounts WHERE name = _input LIMIT 1) IS NOT NULL THEN
    RETURN json_build_object(
      'input_type', 'account_name',
      'input_value', _input
    );
  END IF;

  -- second, positive digit and not name is assumed to be block number
  IF _input SIMILAR TO '(\d+)' THEN
    SELECT hafbe_endpoints.get_head_block_num() INTO __head_block_num;
    IF _input::NUMERIC > __head_block_num THEN
      RETURN hafbe_exceptions.raise_block_num_too_high_exception(_input::NUMERIC, __head_block_num);
    ELSE
      RETURN json_build_object(
        'input_type', 'block_num',
        'input_value', _input
      );
    END IF;
  END IF;

  -- third, if input is 40 char hash, it is validated for transaction or block hash
  -- hash is unknown if failed to validate
  IF _input SIMILAR TO '([a-f0-9]{40})' THEN
    IF (SELECT trx_hash FROM hive.transactions WHERE trx_hash = ('\x' || _input)::BYTEA LIMIT 1) IS NOT NULL THEN
      RETURN json_build_object(
        'input_type', 'transaction_hash',
        'input_value', _input
      );
    ELSE
      __block_num = hafbe_backend.get_block_num(('\x' || _input)::BYTEA);
    END IF;

    IF __input_type IS NULL AND __block_num IS NOT NULL THEN
      RETURN json_build_object(
        'input_type', 'block_hash',
        'input_value', __block_num
      );
    ELSIF __input_type IS NULL AND __block_num IS NULL THEN
      RETURN hafbe_exceptions.raise_unknown_hash_exception(_input::TEXT);
    END IF;
  END IF;

  -- fourth, it is still possible input is partial name, max 50 names returned.
  -- if no matching accounts were found, 'unknown_input' is returned
  SELECT hafbe_backend.find_matching_accounts(_input::TEXT) INTO __accounts_array;
  IF __accounts_array IS NOT NULL THEN
    RETURN json_build_object(
      'input_type', 'account_name_array',
      'input_value', __accounts_array
    );
  ELSE
    RETURN hafbe_exceptions.raise_unknown_input_exception(_input::TEXT);
  END IF;
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

CREATE FUNCTION hafbe_endpoints.get_acc_op_types(_account TEXT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __account_id INT = hafbe_backend.get_account_id(_account);
BEGIN
  RETURN hafbe_backend.get_acc_op_types(__account_id);
END
$$
;

CREATE FUNCTION hafbe_endpoints.get_block_op_types(_block_num INT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN hafbe_backend.get_block_op_types(_block_num);
END
$$
;

CREATE FUNCTION hafbe_endpoints.get_ops_by_account(_account TEXT, _start BIGINT = 9223372036854775807, _limit BIGINT = 1000, _filter SMALLINT[] = ARRAY[]::SMALLINT[])
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __account_id INT;
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

  IF _filter IS NULL THEN
    _filter = ARRAY[]::SMALLINT[];
  END IF;

  SELECT hafbe_backend.get_account_id(_account) INTO __account_id;

  RETURN hafbe_backend.get_ops_by_account(__account_id, _start, _limit, _filter);
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

CREATE FUNCTION hafbe_endpoints.get_ops_by_block(_block_num INT, _start BIGINT = 9223372036854775807, _limit BIGINT = 1000, _filter SMALLINT[] = ARRAY[]::SMALLINT[])
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

  IF _filter IS NULL THEN
    _filter = ARRAY[]::SMALLINT[];
  END IF;

  RETURN hafbe_backend.get_ops_by_block(_block_num, _start, _limit, _filter);
END
$$
;

CREATE FUNCTION hafbe_endpoints.get_transaction(_trx_hash TEXT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  -- _trx_hash TEXT -> BYTEA, __include_reversible = FALSE, __is_legacy_style = FALSE
  RETURN hafah_python.get_transaction_json(('\x' || _trx_hash)::BYTEA, FALSE, FALSE);
END
$$
;

CREATE FUNCTION hafbe_endpoints.get_top_witnesses(_witnesses_number INT = 50)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  IF _witnesses_number IS NULL OR _witnesses_number <= 0 THEN
    _witnesses_number = FALSE;
  END IF;

  RETURN json_agg(witness->>'owner')
  FROM (
    SELECT json_array_elements(hafbe_backend.get_top_witnesses(_witnesses_number)) AS witness
  ) result;
END
$$
;

CREATE FUNCTION hafbe_endpoints.get_witness_by_account(_account TEXT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN hafbe_backend.get_witness_by_account(_account);
END
$$
;

CREATE FUNCTION hafbe_endpoints.get_account(_account TEXT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __account_data JSON = hafbe_backend.get_account(_account);
  __profile_image TEXT;
BEGIN
  SELECT hafbe_backend.parse_profile_picture(__account_data, 'json_metadata') INTO __profile_image;
  IF __profile_image IS NULL THEN
    SELECT hafbe_backend.parse_profile_picture(__account_data, 'posting_json_metadata') INTO __profile_image;
  END IF;
  
  RETURN json_build_object(
    'id', __account_data->>'id',
    'name', _account,
    'profile_image', __profile_image,
    'last_owner_update', __account_data->>'last_owner_update',
    'last_account_update', __account_data->>'last_account_update',
    'created', __account_data->>'created',
    'mined', __account_data->>'mined',
    'recovery_account', __account_data->>'recovery_account',
    'comment_count', __account_data->>'comment_count',
    'post_count', __account_data->>'post_count',
    'can_vote', __account_data->>'can_vote',
    'voting_manabar', __account_data->'voting_manabar',
    'downvote_manabar', __account_data->'downvote_manabar',
    'voting_power', __account_data->>'voting_power',
    'balance', __account_data->>'balance',
    'savings_balance', __account_data->>'savings_balance',
    'hbd_balance', __account_data->>'hbd_balance',
    'savings_withdraw_requests', __account_data->>'savings_withdraw_requests',
    'reward_hbd_balance', __account_data->>'reward_hbd_balance',
    'reward_hive_balance', __account_data->>'reward_hive_balance',
    'reward_vesting_balance', __account_data->>'reward_vesting_balance',
    'reward_vesting_hive', __account_data->>'reward_vesting_hive',
    'vesting_shares', __account_data->>'vesting_shares',
    'delegated_vesting_shares', __account_data->>'delegated_vesting_shares',
    'received_vesting_shares', __account_data->>'received_vesting_shares',
    'vesting_withdraw_rate', __account_data->>'vesting_withdraw_rate',
    'post_voting_power', __account_data->>'post_voting_power',
    'posting_rewards', __account_data->>'posting_rewards',
    'proxied_vsf_votes', __account_data->'proxied_vsf_votes',
    'witnesses_voted_for', __account_data->>'witnesses_voted_for',
    'last_post', __account_data->>'last_post',
    'last_root_post', __account_data->>'last_root_post',
    'last_vote_time', __account_data->>'last_vote_time',
    'vesting_balance', __account_data->>'vesting_balance',
    'reputation', __account_data->>'reputation'
  );
END
$$
;