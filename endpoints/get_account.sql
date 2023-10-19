SET ROLE hafbe_owner;

CREATE SCHEMA IF NOT EXISTS hafbe_endpoints AUTHORIZATION hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_account(_account TEXT) 
RETURNS hafbe_types.account
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  __response_data JSON;
  __json_metadata JSON;
  __posting_json_metadata JSON;
  __profile_image TEXT;
  _account_id INT = hafbe_backend.get_account_id(_account);
BEGIN
RETURN (
WITH select_parameters_from_backend AS MATERIALIZED (
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
    COALESCE(_result_withdraws.delayed_vests, 0) AS delayed_vests,
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
    COALESCE(_result_votes.witness_votes, '[]') AS witness_votes,
    COALESCE(_result_votes.witnesses_voted_for, 0) AS witnesses_voted_for,
    COALESCE(_result_votes.proxied_vsf_votes, '[]') AS proxied_vsf_votes,
    COALESCE(_result_proxy.get_account_proxy, '') AS proxy_name,
    COALESCE(_result_count.get_account_ops_count, 0) AS ops_count,
    EXISTS (SELECT NULL FROM hafbe_app.current_witnesses WHERE witness_id = _account_id) AS is_witness
  FROM
    (SELECT * FROM btracker_endpoints.get_account_balances(_account_id)) AS _result_balance,
    (SELECT * FROM btracker_endpoints.get_account_withdraws(_account_id)) AS _result_withdraws,
    (SELECT * FROM btracker_endpoints.get_account_delegations(_account_id)) AS _result_vest_balance,
    (SELECT * FROM hafbe_backend.get_json_metadata(_account_id)) AS _result_json_metadata,
    (SELECT * FROM btracker_endpoints.get_account_rewards(_account_id)) AS _result_rewards,
    (SELECT * FROM btracker_endpoints.get_account_savings(_account_id)) AS _result_savings,
    (SELECT * FROM btracker_endpoints.get_account_info_rewards(_account_id)) AS _result_curation_posting,
    (SELECT * FROM hafbe_backend.get_last_post_vote_time(_account_id)) AS _result_post,
    (SELECT * FROM hafbe_backend.get_account_parameters(_account_id)) AS _result_parameters,
    (SELECT * FROM hafbe_backend.get_account_votes(_account_id)) AS _result_votes,
    (SELECT * FROM hafbe_backend.get_account_proxy(_account_id)) AS _result_proxy,
    (SELECT * FROM hafbe_backend.get_account_ops_count(_account_id)) AS _result_count
  )
  SELECT ROW(
  _account_id,
  _account,
--'owner', __response_data->'owner', --work in progress 10
--'active', __response_data->'active', --work in progress 10
--'posting', __response_data->'posting', --work in progress 10
--'memo_key', __response_data->>'memo_key', --work in progress 10
  profile_image,
  json_metadata,
  posting_json_metadata,
--'last_owner_update', __response_data->>'last_owner_update', --work in progress 10
--'last_account_update', __response_data->>'last_account_update', --work in progress 10
  proxy_name,
  created,
  mined,
  recovery_account, 
  last_account_recovery,
  can_vote,
-- 'voting_manabar', __response_data->'voting_manabar', --can't be track it without consensus_state_provider
-- 'downvote_manabar', __response_data->'downvote_manabar', --can't be track it without consensus_state_provider
-- 'voting_power', __response_data->>'voting_power', --can't be track it without consensus_state_provider
  hive_balance,
  hive_savings::BIGINT,
  hbd_balance,
  hbd_savings::BIGINT,
  savings_withdraw_requests,
  hbd_rewards::BIGINT,
  hive_rewards::BIGINT,
  vests_rewards::BIGINT,
  hive_vesting_rewards::BIGINT,
  vesting_shares,
  delegated_vests,
  received_vests,
  vesting_withdraw_rate,
  to_withdraw,
  withdrawn,
  withdraw_routes,
  post_voting_power_vests,
  posting_rewards,
  curation_rewards,
  proxied_vsf_votes,
  witnesses_voted_for,
  post_count,
  last_post,
  last_root_post,
  last_vote_time,
  delayed_vests,
  vesting_balance_hive, 
-- 'reputation', __response_data->>'reputation', --work in progress
  witness_votes,
  ops_count,
  is_witness)
FROM select_parameters_from_backend
);

END
$$
;

RESET ROLE;
