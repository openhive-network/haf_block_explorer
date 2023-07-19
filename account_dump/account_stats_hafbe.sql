DROP TYPE IF EXISTS hafbe_backend.account_type CASCADE;
CREATE TYPE hafbe_backend.account_type AS
(
  name TEXT,
  balance BIGINT,
  hbd_balance BIGINT,
  vesting_shares BIGINT,
  savings_balance BIGINT,
  savings_hbd_balance BIGINT,
  savings_withdraw_requests INT,
  reward_hbd_balance BIGINT,
  reward_hive_balance BIGINT,
  reward_vesting_balance BIGINT,
  reward_vesting_hive BIGINT,
  delegated_vesting_shares BIGINT,
  received_vesting_shares BIGINT,
  withdraw_routes INT,
  post_voting_power BIGINT,
  posting_rewards BIGINT,
  last_post TIMESTAMP,
  last_root_post TIMESTAMP,
  last_vote_time TIMESTAMP,
  post_count INT
);

CREATE OR REPLACE FUNCTION hafbe_backend.get_account_setof(_account TEXT)
RETURNS hafbe_backend.account_type
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  __account_id INT := (SELECT id FROM hive.accounts_view WHERE name = _account);
  __result hafbe_backend.account_type;
BEGIN
  SELECT
    _account,
    COALESCE(_result_balance.hive_balance, 0) AS hive_balance,
    COALESCE(_result_balance.hbd_balance, 0)AS hbd_balance,
    COALESCE(_result_balance.vesting_shares, 0) AS vesting_shares,
    COALESCE(_result_savings.hive_savings, 0) AS hive_savings,
    COALESCE(_result_savings.hbd_savings, 0) AS hbd_savings,
    COALESCE(_result_savings.savings_withdraw_requests, 0) AS savings_withdraw_requests,
    COALESCE(_result_rewards.hbd_rewards, 0) AS hbd_rewards,
    COALESCE(_result_rewards.hive_rewards, 0) AS hive_rewards,
    COALESCE(_result_rewards.vests_rewards, 0) AS vests_rewards,
    COALESCE(_result_rewards.hive_vesting_rewards, 0) AS hive_vesting_rewards,
    COALESCE(_result_vest_balance.delegated_vests, 0) AS delegated_vests,
    COALESCE(_result_vest_balance.received_vests, 0) AS received_vests,
    COALESCE(_result_withdraws.withdraw_routes, 0) AS withdraw_routes,
    COALESCE(_result_balance.post_voting_power_vests, 0) AS post_voting_power_vests,
    COALESCE(_result_curation_posting.posting_rewards, 0) AS posting_rewards,
    COALESCE(_result_post.last_post, '1970-01-01T00:00:00') AS last_post,
    COALESCE(_result_post.last_root_post, '1970-01-01T00:00:00') AS last_root_post,
    COALESCE(_result_post.last_vote_time, '1970-01-01T00:00:00') AS last_vote_time,
    COALESCE(_result_post.post_count, 0) AS post_count
  INTO __result
  FROM
    (SELECT * FROM hafbe_backend.get_btracker_account_balance(__account_id)) AS _result_balance,
    (SELECT * FROM hafbe_backend.get_account_withdraws(__account_id)) AS _result_withdraws,
    (SELECT * FROM hafbe_backend.get_btracker_vests_balance(__account_id)) AS _result_vest_balance,
    (SELECT * FROM hafbe_backend.get_account_rewards(__account_id)) AS _result_rewards,
    (SELECT * FROM hafbe_backend.get_account_savings(__account_id)) AS _result_savings,
    (SELECT * FROM hafbe_backend.get_account_info_rewards(__account_id)) AS _result_curation_posting,
    (SELECT * FROM hafbe_backend.get_last_post_vote_time(__account_id)) AS _result_post;

  RETURN __result;
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_backend.compare_differing_account(_account TEXT)
RETURNS SETOF hafbe_backend.account_type
LANGUAGE 'plpgsql'
STABLE
AS
$$
BEGIN
  RETURN QUERY SELECT 
    name,
    balance,
    hbd_balance,
    vesting_shares,
    savings_balance,
    savings_hbd_balance,
    savings_withdraw_requests,
    reward_hbd_balance,
    reward_hive_balance,
    reward_vesting_balance,
    reward_vesting_hive,
    delegated_vesting_shares,
    received_vesting_shares,
    withdraw_routes,
    post_voting_power,
    posting_rewards,
    last_post,
    last_root_post,
    last_vote_time,
    post_count
  FROM hafbe_backend.account_balances WHERE name = _account
  UNION ALL
SELECT * FROM hafbe_backend.get_account_setof(_account);

END
$$
;
