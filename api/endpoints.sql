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

CREATE FUNCTION hafbe_endpoints.get_op_types()
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN hafbe_backend.get_op_types();
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

CREATE FUNCTION hafbe_endpoints.get_ops_by_account(_account TEXT, _top_op_id BIGINT = 9223372036854775807, _limit BIGINT = 1000, _filter SMALLINT[] = ARRAY[]::SMALLINT[], _date_start TIMESTAMP = NULL, _date_end TIMESTAMP = NULL)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __account_id INT;
BEGIN
  IF _top_op_id IS NULL OR _top_op_id < 0 THEN
    _top_op_id = 9223372036854775807;
  END IF;

  IF _limit IS NULL OR _limit <= 0 THEN
    _limit = 1000;
  END IF;

  IF _top_op_id < (_limit - 1) THEN
    RETURN hafbe_exceptions.raise_ops_limit_exception(_top_op_id, _limit);
  END IF;

  IF _filter IS NULL THEN
    _filter = ARRAY[]::SMALLINT[];
  END IF;

  SELECT hafbe_backend.get_account_id(_account) INTO __account_id;

  RETURN hafbe_backend.get_ops_by_account(__account_id, _top_op_id, _limit, _filter, _date_start, _date_end);
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

CREATE FUNCTION hafbe_endpoints.get_ops_by_block(_block_num INT, _top_op_id BIGINT = 9223372036854775807, _limit BIGINT = 1000, _filter SMALLINT[] = ARRAY[]::SMALLINT[])
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  IF _top_op_id IS NULL OR _top_op_id < 0 THEN
    _top_op_id = 9223372036854775807;
  END IF;

  IF _limit IS NULL OR _limit <= 0 THEN
    _limit = 1000;
  END IF;

  IF _top_op_id < (_limit - 1) THEN
    RETURN hafbe_exceptions.raise_ops_limit_exception(_top_op_id, _limit);
  END IF;

  IF _filter IS NULL THEN
    _filter = ARRAY[]::SMALLINT[];
  END IF;

  RETURN hafbe_backend.get_ops_by_block(_block_num, _top_op_id, _limit, _filter);
END
$$
;

CREATE FUNCTION hafbe_endpoints.get_transaction(_trx_hash TEXT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  -- _trx_hash TEXT -> BYTEA, __include_reversible = TRUE, __is_legacy_style = FALSE
  RETURN hafah_python.get_transaction_json(('\x' || _trx_hash)::BYTEA, TRUE, FALSE);
END
$$
;

CREATE FUNCTION hafbe_endpoints.get_witness_voters(_witness TEXT, _limit INT = 1000, _order_by TEXT = 'vests', _order_is TEXT = 'desc')
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __witness_id INT = hafbe_backend.get_account_id(_witness);
BEGIN
  IF _limit IS NULL OR _limit <= 0 THEN
    _limit = 1000;
  END IF;

  IF _order_by NOT SIMILAR TO '(account|vests|account_vests|proxied_vests|timestamp)' THEN
    RETURN hafbe_exceptions.raise_no_such_column_exception(_order_by);
  END IF;
  IF _order_by IS NULL THEN
    _order_by = 'vests';
  END IF;

  IF _order_is NOT SIMILAR TO '(asc|desc)' THEN
    RETURN hafbe_exceptions.raise_no_such_order_exception(_order_is);
  END IF;
  IF _order_is IS NULL THEN
    _order_is = 'desc';
  END IF;

  RETURN hafbe_backend.get_witness_voters(__witness_id, _limit, _order_by, _order_is);
END
$$
;

CREATE FUNCTION hafbe_endpoints.get_witnesses(_limit INT = 50, _order_by TEXT = 'vests', _order_is TEXT = 'desc')
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  IF _limit IS NULL OR _limit <= 0 THEN
    _limit = 50;
  END IF;

  IF _order_by NOT SIMILAR TO
    '(witness|url|votes|votes_daily_change|voters_num|voters_num_daily_change|price_feed|bias|feed_age|block_size|signing_key|version)' THEN
    RETURN hafbe_exceptions.raise_no_such_column_exception(_order_by);
  END IF;
  IF _order_by IS NULL THEN
    _order_by = 'vests';
  END IF;

  IF _order_is NOT SIMILAR TO '(asc|desc)' THEN
    RETURN hafbe_exceptions.raise_no_such_order_exception(_order_is);
  END IF;
  IF _order_is IS NULL THEN
    _order_is = 'desc';
  END IF;

  RETURN hafbe_backend.get_witnesses(_limit, _order_by, _order_is);
END
$$
;

CREATE FUNCTION hafbe_endpoints.get_account(_account TEXT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __account_data JSON;
  __profile_image TEXT;
  __response_data JSON;
BEGIN
  SELECT data FROM hafbe_app.hived_account_cache WHERE account = _account INTO __response_data;

  IF __response_data IS NOT NULL THEN
    RETURN __response_data;
  ELSE
    SELECT hafbe_backend.get_account(_account) INTO __account_data;

    SELECT hafbe_backend.parse_profile_picture(__account_data, 'json_metadata') INTO __profile_image;
    IF __profile_image IS NULL THEN
      SELECT hafbe_backend.parse_profile_picture(__account_data, 'posting_json_metadata') INTO __profile_image;
    END IF;
    
    SELECT json_build_object(
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
    ) INTO __response_data;

    INSERT INTO hafbe_app.hived_account_cache (account, data)
    SELECT _account, __response_data
    ON CONFLICT DO NOTHING;

    RETURN __response_data;
  END IF;
END
$$
;
