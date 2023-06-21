--ACCOUNT KEYAUTH

DROP TYPE IF EXISTS hafbe_endpoints.account_keyauth CASCADE;
CREATE TYPE hafbe_endpoints.account_keyauth AS
(
  key_auth TEXT,
  authority_kind hive.authority_type
);

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_account_keyauth(_account TEXT)
RETURNS SETOF hafbe_endpoints.account_keyauth
LANGUAGE 'plpgsql'
AS
$$
DECLARE
BEGIN

RETURN QUERY SELECT key_auth, authority_kind 
FROM hive.hafbe_app_keyauth 
WHERE account_name= _account 
ORDER BY authority_kind ASC;

END
$$
;

--ACCOUNT SAVINGS

DROP TYPE IF EXISTS hafbe_endpoints.current_account_savings CASCADE;
CREATE TYPE hafbe_endpoints.current_account_savings AS
(
  hbd_savings numeric,
  hive_savings numeric,
  savings_withdraw_requests INT
);

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_current_account_savings(_account TEXT)
RETURNS hafbe_endpoints.current_account_savings
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __result hafbe_endpoints.current_account_savings;
BEGIN

SELECT  
  MAX(CASE WHEN nai = 13 THEN saving_balance END) AS hbd,
  MAX(CASE WHEN nai = 21 THEN saving_balance END) AS hive
INTO __result.hbd_savings, __result.hive_savings
FROM btracker_app.current_account_savings WHERE account= _account;

SELECT SUM (savings_withdraw_requests) AS total
INTO __result.savings_withdraw_requests
FROM btracker_app.current_account_savings
WHERE account= _account;

RETURN __result;
END
$$
;

--ACCOUNT REWARDS

DROP TYPE IF EXISTS hafbe_endpoints.current_account_rewards CASCADE;
CREATE TYPE hafbe_endpoints.current_account_rewards AS
(
  hbd_rewards numeric,
  hive_rewards numeric,
  vests_rewards numeric,
  hive_vesting_rewards numeric
);

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_current_account_rewards(_account TEXT)
RETURNS hafbe_endpoints.current_account_rewards
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __result hafbe_endpoints.current_account_rewards;
BEGIN

SELECT  
  MAX(CASE WHEN nai = 13 THEN balance END) AS hbd,
  MAX(CASE WHEN nai = 21 THEN balance END) AS hive,
  MAX(CASE WHEN nai = 37 THEN balance END) AS vests,
  MAX(CASE WHEN nai = 38 THEN balance END) AS vesting_hive
INTO __result
FROM btracker_app.current_account_rewards WHERE account= _account;

RETURN __result;
END
$$
;

--ACCOUNT METADATA

DROP TYPE IF EXISTS hafbe_endpoints.json_metadata CASCADE;
CREATE TYPE hafbe_endpoints.json_metadata AS
(
  json_metadata TEXT,
  posting_json_metadata TEXT
);

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_json_metadata(_account TEXT)
RETURNS hafbe_endpoints.json_metadata
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  _account_id INT;
  __result hafbe_endpoints.json_metadata;
BEGIN
  SELECT id INTO _account_id FROM hive.accounts_view WHERE name = _account;

  SELECT json_metadata, posting_json_metadata FROM hive.hafbe_app_metadata 
    INTO __result WHERE account_id= _account_id;

RETURN __result;

END
$$
;

--ACCOUNT DELEGATED AND RECEIVED VESTS

DROP TYPE IF EXISTS hafbe_endpoints.btracker_vests_balance CASCADE;
CREATE TYPE hafbe_endpoints.btracker_vests_balance AS
(
  delegated_vests numeric,
  received_vests numeric
);

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_btracker_vests_balance(_account TEXT)
RETURNS hafbe_endpoints.btracker_vests_balance
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __result hafbe_endpoints.btracker_vests_balance;
BEGIN

SELECT delegated_vests, received_vests INTO __result FROM btracker_app.current_account_vests WHERE account= _account;
RETURN __result;

END
$$
;

--ACCOUNT HIVE, HBD, VEST BALANCES

DROP TYPE IF EXISTS hafbe_endpoints.btracker_account_balance CASCADE;
CREATE TYPE hafbe_endpoints.btracker_account_balance AS
(
  hbd_balance numeric,
  hive_balance numeric,
  vesting_shares numeric
);

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_btracker_account_balance(_account TEXT)
RETURNS hafbe_endpoints.btracker_account_balance
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __result hafbe_endpoints.btracker_account_balance;
BEGIN

SELECT  
  MAX(CASE WHEN nai = 13 THEN balance END) AS hbd,
  MAX(CASE WHEN nai = 21 THEN balance END) AS hive, 
  MAX(CASE WHEN nai = 37 THEN balance END) AS vest 
INTO __result
FROM btracker_app.current_account_balances WHERE account= _account;

RETURN __result;

END
$$
;


CREATE OR REPLACE FUNCTION hafbe_endpoints.get_account(_account TEXT)
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
    'id', __response_data->>'id', --OK
    'name', _account, --OK
    'owner', __response_data->'owner', --work in progress
    'active', __response_data->'active', --work in progress
    'posting', __response_data->'posting', --work in progress
    'memo_key', __response_data->>'memo_key', --??
    'profile_image', __profile_image, --OK
    'json_metadata', __json_metadata, --OK
    'posting_json_metadata', __posting_json_metadata, --OK
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
    'balance', __response_data->>'balance', --OK
    'savings_balance', __response_data->>'savings_balance', --OK
    'hbd_balance', __response_data->>'hbd_balance', --OK
    --hbd_saving_balance OK
    'savings_withdraw_requests', __response_data->>'savings_withdraw_requests', --OK
    'reward_hbd_balance', __response_data->>'reward_hbd_balance', --OK
    'reward_hive_balance', __response_data->>'reward_hive_balance', --OK
    'reward_vesting_balance', __response_data->>'reward_vesting_balance', --OK
    'reward_vesting_hive', __response_data->>'reward_vesting_hive', --OK
    'vesting_shares', __response_data->>'vesting_shares', --OK 
    'delegated_vesting_shares', __response_data->>'delegated_vesting_shares', --OK
    'received_vesting_shares', __response_data->>'received_vesting_shares', --OK
    'vesting_withdraw_rate', __response_data->>'vesting_withdraw_rate',
    'post_voting_power', __response_data->>'post_voting_power',
    'posting_rewards', __response_data->>'posting_rewards',
    'proxied_vsf_votes', __response_data->'proxied_vsf_votes',
    'witnesses_voted_for', __response_data->>'witnesses_voted_for',
    'last_post', __response_data->>'last_post',
    'last_root_post', __response_data->>'last_root_post',
    'last_vote_time', __response_data->>'last_vote_time',
    'vesting_balance', __response_data->>'vesting_balance', --OK, NOT USED ANYMORE (ALWAYS 0)
    'reputation', __response_data->>'reputation', --work in progress
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

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_account_resource_credits(_account TEXT)
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
