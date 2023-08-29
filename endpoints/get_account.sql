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
  FROM hive.accounts_view WHERE name = _account;

  SELECT hafbe_backend.get_account(_account) INTO __response_data;

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
  COALESCE(_result_json_metadata.json_metadata,'') AS json_metadata,
  COALESCE(_result_json_metadata.posting_json_metadata, '') AS posting_json_metadata,
  COALESCE((SELECT hafbe_backend.parse_profile_picture(_result_json_metadata.json_metadata, _result_json_metadata.posting_json_metadata)), '') AS profile_image,
  COALESCE(_result_rewards.hbd_rewards, 0) AS hbd_rewards,
  COALESCE(_result_rewards.hive_rewards, 0) AS hive_rewards,
  COALESCE(_result_rewards.vests_rewards, 0) AS vests_rewards,
  COALESCE(_result_rewards.hive_vesting_rewards, 0) AS hive_vesting_rewards,
  COALESCE(_result_savings.hbd_savings, 0) AS hbd_savings,
  COALESCE(_result_savings.hive_savings, 0) AS hive_savings,
  COALESCE(_result_savings.savings_withdraw_requests, 0) AS savings_withdraw_requests,
  COALESCE(_result_curation_posting.posting_rewards, 0) AS posting_rewards,
  COALESCE(_result_curation_posting.curation_rewards, 0) AS curation_rewards,
  COALESCE(_result_post.last_post, '1970-01-01T00:00:00') AS last_post,
  COALESCE(_result_post.last_root_post, '1970-01-01T00:00:00') AS last_root_post,
  COALESCE(_result_post.last_vote_time, '1970-01-01T00:00:00') AS last_vote_time,
  COALESCE(_result_post.post_count, 0) AS post_count,
  COALESCE(_result_parameters.can_vote, TRUE) AS can_vote,
  COALESCE(_result_parameters.mined, TRUE) AS mined,
  COALESCE(_result_parameters.recovery_account, 'steem') AS recovery_account,
  COALESCE(_result_parameters.last_account_recovery, '1970-01-01T00:00:00') AS last_account_recovery,
  COALESCE(_result_parameters.created,'1970-01-01T00:00:00') AS created,
  FROM
  (SELECT * FROM hafbe_backend.get_btracker_account_balance(__account_id)) AS _result_balance,
  (SELECT * FROM hafbe_backend.get_account_withdraws(__account_id)) AS _result_withdraws,
  (SELECT * FROM hafbe_backend.get_btracker_vests_balance(__account_id)) AS _result_vest_balance,
  (SELECT * FROM hafbe_backend.get_json_metadata(__account_id)) AS _result_json_metadata,
  (SELECT * FROM hafbe_backend.get_account_rewards(__account_id)) AS _result_rewards,
  (SELECT * FROM hafbe_backend.get_account_savings(__account_id)) AS _result_savings,
  (SELECT * FROM hafbe_backend.get_account_info_rewards(__account_id)) AS _result_curation_posting,
  (SELECT * FROM hafbe_backend.get_last_post_vote_time(__account_id)) AS _result_post,
  (SELECT * FROM hafbe_backend.get_account_parameters(__account_id)) AS _result_parameters,
  )

  SELECT json_build_object(
    'id', __account_id, --OK
    'name', _account, --OK
    'owner', __response_data->'owner', --work in progress 10
    'active', __response_data->'active', --work in progress 10
    'posting', __response_data->'posting', --work in progress 10
    'memo_key', __response_data->>'memo_key', --work in progress 10
    'profile_image', profile_image, --work in progress 10
    'json_metadata', json_metadata, --work in progress 10
    'posting_json_metadata', posting_json_metadata, --work in progress 10
    'last_owner_update', __response_data->>'last_owner_update', --work in progress 10
    'last_account_update', __response_data->>'last_account_update', --work in progress 10
    'created', created, --work in progress 9,23,41,80
    'mined', mined, --work in progress 9,23,41,  14,30
    'recovery_account', recovery_account, --work in progress 76
    'last_account_recovery', last_account_recovery, --work in progress 25
    'can_vote', can_vote, --work in progress 36
    
  --  'voting_manabar', __response_data->'voting_manabar', --can't be track it without consensus_state_provider
  --  'downvote_manabar', __response_data->'downvote_manabar', --can't be track it without consensus_state_provider
  --  'voting_power', __response_data->>'voting_power', --can't be track it without consensus_state_provider
    'balance', hive_balance, --OK
    'savings_balance', hive_savings, --OK
    'hbd_balance', hbd_balance, --OK
    'hbd_saving_balance', hbd_savings, --OK
    'savings_withdraw_requests', savings_withdraw_requests, --OK
    'reward_hbd_balance', hbd_rewards, --OK
    'reward_hive_balance', hive_rewards, --OK
    'reward_vesting_balance', vests_rewards, --OK
    'reward_vesting_hive', hive_vesting_rewards, --OK, may have slight diffrences
    'vesting_shares', vesting_shares, --OK 
    'delegated_vesting_shares', delegated_vests, --OK
    'received_vesting_shares', received_vests, --OK
    'vesting_withdraw_rate', vesting_withdraw_rate, --OK
    'to_withdraw', to_withdraw,--OK
    'withdrawn', withdrawn,--OK
    'withdraw_routes', withdraw_routes,--OK
    'post_voting_power', post_voting_power_vests, --OK
    'posting_rewards', posting_rewards, --OK
    'curation_rewards', curation_rewards, --OK, may have slight diffrences
    'post_count', post_count, --OK
    'last_post', last_post, --OK
    'last_root_post', last_root_post, --OK
    'last_vote_time', last_vote_time, --OK
    'vesting_balance', vesting_balance_hive, --OK
    'reputation', __response_data->>'reputation', --work in progress
    'witness_votes', __response_data->'witness_votes'
  ) INTO __response_data
   FROM btracker_balance;

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
