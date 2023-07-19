CREATE OR REPLACE FUNCTION hafbe_endpoints.get_account(_account TEXT)
RETURNS JSON
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  __response_data JSON;
  __json_metadata JSON;
  __posting_json_metadata JSON;
  __profile_image TEXT;
  __account_id INT;
BEGIN
  SELECT id INTO __account_id
  FROM hive.hafbe_app_accounts_view WHERE name = _account;

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

  WITH btracker_balance AS 
  (
  SELECT
  COALESCE(_result_balance.hbd_balance, 0)AS hbd_balance,
  COALESCE(_result_balance.hive_balance, 0) AS hive_balance,
  COALESCE(_result_balance.vesting_shares, 0) AS vesting_shares,
  COALESCE(_result_balance.vesting_balance_hive, 0) AS vesting_balance_hive,
  COALESCE(_result_balance.post_voting_power_vests, 0) AS post_voting_power_vests,
  COALESCE(_result_withdraws.vesting_withdraw_rate, 0) AS vesting_withdraw_rate,
  COALESCE(_result_withdraws.to_withdraw, 0) AS to_withdraw,
  COALESCE(_result_withdraws.withdrawn, 0) AS withdrawn,
  COALESCE(_result_withdraws.withdraw_routes, 0) AS withdraw_routes,
  COALESCE(_result_vest_balance.delegated_vests, 0) AS delegated_vests,
  COALESCE(_result_vest_balance.received_vests, 0) AS received_vests,
  _result_json_metadata.json_metadata AS json_metadata,
  _result_json_metadata.posting_json_metadata AS posting_json_metadata,
  COALESCE(_result_rewards.hbd_rewards, 0) AS hbd_rewards,
  COALESCE(_result_rewards.hive_rewards, 0) AS hive_rewards,
  COALESCE(_result_rewards.vests_rewards, 0) AS vests_rewards,
  COALESCE(_result_rewards.hive_vesting_rewards, 0) AS hive_vesting_rewards,
  COALESCE(_result_savings.hbd_savings, 0) AS hbd_savings,
  COALESCE(_result_savings.hive_savings, 0) AS hive_savings,
  COALESCE(_result_savings.savings_withdraw_requests, 0) AS savings_withdraw_requests,
  COALESCE(_result_curation_posting.posting_rewards, 0) AS posting_rewards,
  COALESCE(_result_curation_posting.curation_rewards, 0) AS curation_rewards
  FROM
  (SELECT * FROM hafbe_endpoints.get_btracker_account_balance(__account_id)) AS _result_balance,
  (SELECT * FROM hafbe_endpoints.get_current_account_withdraws(__account_id)) AS _result_withdraws,
  (SELECT * FROM hafbe_endpoints.get_btracker_vests_balance(__account_id)) AS _result_vest_balance,
  (SELECT * FROM hafbe_endpoints.get_json_metadata(__account_id)) AS _result_json_metadata,
  (SELECT * FROM hafbe_endpoints.get_current_account_rewards(__account_id)) AS _result_rewards,
  (SELECT * FROM hafbe_endpoints.get_current_account_savings(__account_id)) AS _result_savings,
  (SELECT * FROM hafbe_endpoints.get_account_posting_curation_rewards(__account_id)) AS _result_curation_posting
  )

  SELECT json_build_object(
    'id', __account_id, --OK
    'name', _account, --OK
    'owner', __response_data->'owner', --work in progress
    'active', __response_data->'active', --work in progress
    'posting', __response_data->'posting', --work in progress
    'memo_key', __response_data->>'memo_key', --??
    'profile_image', __profile_image, --OK
    'json_metadata', json_metadata, --OK
    'posting_json_metadata', posting_json_metadata, --OK
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
    'balance', hive_balance, --OK
    'savings_balance', hive_savings, --OK
    'hbd_balance', hbd_balance, --OK
    'hbd_saving_balance', hbd_savings, --OK
    'savings_withdraw_requests', savings_withdraw_requests, --OK
    'reward_hbd_balance', hbd_rewards, --OK
    'reward_hive_balance', hive_rewards, --OK
    'reward_vesting_balance', vests_rewards, --OK
    'reward_vesting_hive', hive_vesting_rewards, --OK
    'vesting_shares', vesting_shares, --OK 
    'delegated_vesting_shares', delegated_vests, --OK
    'received_vesting_shares', received_vests, --OK
    'vesting_withdraw_rate', vesting_withdraw_rate, --OK
    'to_withdraw', to_withdraw,--OK
    'withdrawn', withdrawn,--OK
    'withdraw_routes', withdraw_routes,--OK
    'post_voting_power', post_voting_power_vests, --OK
    'posting_rewards', posting_rewards, --OK
    'curation_rewards', curation_rewards, --OK
    'proxied_vsf_votes', __response_data->'proxied_vsf_votes',
    'witnesses_voted_for', __response_data->>'witnesses_voted_for',
    'last_post', __response_data->>'last_post',
    'last_root_post', __response_data->>'last_root_post',
    'last_vote_time', __response_data->>'last_vote_time',
    'vesting_balance', vesting_balance_hive, --OK
    'reputation', __response_data->>'reputation', --work in progress
    'witness_votes', __response_data->'witness_votes'
  ) INTO __response_data
   FROM btracker_balance;

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
LANGUAGE 'plpgsql' STABLE
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
