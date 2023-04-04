DROP TYPE IF EXISTS hafbe_endpoints.btracker_account_balance CASCADE;
CREATE TYPE hafbe_endpoints.btracker_account_balance AS
(
  hbd_balance INT,
  hive_balance INT,
  vesting_shares BIGINT
);

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_btracker_account_balance(_account TEXT)
RETURNS hafbe_endpoints.btracker_account_balance
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  hive_amount TEXT;
  hbd_amount TEXT;
  vest_amount TEXT;
  __result hafbe_endpoints.btracker_account_balance;
BEGIN

SELECT  
  MAX(CASE WHEN nai = 13 THEN balance END) AS hbd,
  MAX(CASE WHEN nai = 21 THEN balance END) AS hive, 
  MAX(CASE WHEN nai = 37 THEN balance END) AS vest 
INTO hbd_amount, hive_amount, vest_amount
FROM btracker_app.current_account_balances WHERE account= _account;

  __result.hbd_balance = hbd_amount;
  __result.hive_balance = hive_amount;
  __result.vesting_shares = vest_amount;

RETURN __result;

END
$$
;


CREATE FUNCTION hafbe_endpoints.get_account(_account TEXT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __response_data JSON;
  __json_metadata JSON;
  __posting_json_metadata JSON;
  __profile_image TEXT;
BEGIN
  SELECT INTO __response_data
    data
  FROM hafbe_app.hived_account_cache
  WHERE account = _account AND (NOW() - last_updated_at)::INTERVAL >= '1 hour'::INTERVAL;

  IF __response_data IS NOT NULL THEN
    RETURN __response_data;
  END IF;

  SELECT hafbe_backend.get_account(_account) INTO __response_data;

  SELECT hafbe_backend.parse_profile_picture(__response_data, 'json_metadata') INTO __profile_image;
  IF __profile_image IS NULL THEN
    SELECT hafbe_backend.parse_profile_picture(__response_data, 'posting_json_metadata') INTO __profile_image;
  END IF;

  BEGIN
    SELECT TRIM(BOTH '"' FROM __response_data->>'json_metadata')::JSON INTO __json_metadata;
  EXCEPTION WHEN others THEN
    SELECT NULL INTO __json_metadata;
  END;

  BEGIN
    SELECT TRIM(BOTH '"' FROM __response_data->>'posting_json_metadata')::JSON INTO __posting_json_metadata;
  EXCEPTION WHEN others THEN
    SELECT NULL INTO __posting_json_metadata;
  END;

  SELECT json_build_object(
    'id', __response_data->>'id',
    'name', _account,
    'owner', __response_data->'owner',
    'active', __response_data->'active',
    'posting', __response_data->'posting',
    'memo_key', __response_data->>'memo_key',
    'profile_image', __profile_image,
    'json_metadata', __json_metadata,
    'posting_json_metadata', __posting_json_metadata,
    'last_owner_update', __response_data->>'last_owner_update',
    'last_account_update', __response_data->>'last_account_update',
    'created', __response_data->>'created',
    'mined', __response_data->>'mined',
    'recovery_account', __response_data->>'recovery_account',
    'comment_count', __response_data->>'comment_count',
    'post_count', __response_data->>'post_count',
    'can_vote', __response_data->>'can_vote',
    'voting_manabar', __response_data->'voting_manabar',
    'downvote_manabar', __response_data->'downvote_manabar',
    'voting_power', __response_data->>'voting_power',
    'balance', __response_data->>'balance',
    'savings_balance', __response_data->>'savings_balance',
    'hbd_balance', __response_data->>'hbd_balance',
    'savings_withdraw_requests', __response_data->>'savings_withdraw_requests',
    'reward_hbd_balance', __response_data->>'reward_hbd_balance',
    'reward_hive_balance', __response_data->>'reward_hive_balance',
    'reward_vesting_balance', __response_data->>'reward_vesting_balance',
    'reward_vesting_hive', __response_data->>'reward_vesting_hive',
    'vesting_shares', __response_data->>'vesting_shares',
    'delegated_vesting_shares', __response_data->>'delegated_vesting_shares',
    'received_vesting_shares', __response_data->>'received_vesting_shares',
    'vesting_withdraw_rate', __response_data->>'vesting_withdraw_rate',
    'post_voting_power', __response_data->>'post_voting_power',
    'posting_rewards', __response_data->>'posting_rewards',
    'proxied_vsf_votes', __response_data->'proxied_vsf_votes',
    'witnesses_voted_for', __response_data->>'witnesses_voted_for',
    'last_post', __response_data->>'last_post',
    'last_root_post', __response_data->>'last_root_post',
    'last_vote_time', __response_data->>'last_vote_time',
    'vesting_balance', __response_data->>'vesting_balance',
    'reputation', __response_data->>'reputation',
    'witness_votes', __response_data->'witness_votes'
  ) INTO __response_data;

  INSERT INTO hafbe_app.hived_account_cache (account, data, last_updated_at)
  SELECT _account, __response_data, NOW()
  ON CONFLICT ON CONSTRAINT pk_hived_account_cache DO
  UPDATE SET
    data = EXCLUDED.data,
    last_updated_at = EXCLUDED.last_updated_at
  ;

  RETURN __response_data;
END
$$
;

CREATE FUNCTION hafbe_endpoints.get_account_resource_credits(_account TEXT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __response_data JSON;
BEGIN
  SELECT INTO __response_data
    data
  FROM hafbe_app.hived_account_resource_credits_cache
  WHERE account = _account AND (NOW() - last_updated_at)::INTERVAL >= '1 hour'::INTERVAL;

  IF __response_data IS NULL THEN
    SELECT hafbe_backend.get_account_resource_credits(_account) INTO __response_data;

    INSERT INTO hafbe_app.hived_account_resource_credits_cache (account, data, last_updated_at)
    SELECT _account, __response_data, NOW()
    ON CONFLICT ON CONSTRAINT pk_hived_account_resource_credits_cache DO
    UPDATE SET
      data = EXCLUDED.data,
      last_updated_at = EXCLUDED.last_updated_at
    ;
  END IF;

  RETURN __response_data;
END
$$
;
