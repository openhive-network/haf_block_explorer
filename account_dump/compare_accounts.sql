CREATE TABLE IF NOT EXISTS hafbe_backend.differing_accounts (
  account_name TEXT
);

CREATE OR REPLACE FUNCTION hafbe_backend.compare_accounts()
RETURNS VOID
LANGUAGE 'plpgsql'
VOLATILE
AS
$$
BEGIN
WITH account_balances AS (
  SELECT 
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
  FROM hafbe_backend.account_balances
)
INSERT INTO hafbe_backend.differing_accounts
SELECT account_balances.name
FROM account_balances
JOIN hafbe_backend.get_account_setof(account_balances.name) AS _current_account_stats
ON _current_account_stats.name = account_balances.name
WHERE account_balances.balance <> _current_account_stats.balance 
  OR account_balances.hbd_balance <> _current_account_stats.hbd_balance
  OR account_balances.vesting_shares <> _current_account_stats.vesting_shares
  OR account_balances.savings_balance <> _current_account_stats.savings_balance
  OR account_balances.savings_hbd_balance <> _current_account_stats.savings_hbd_balance
  OR account_balances.savings_withdraw_requests <> _current_account_stats.savings_withdraw_requests
  OR account_balances.reward_hbd_balance <> _current_account_stats.reward_hbd_balance
  OR account_balances.reward_hive_balance <> _current_account_stats.reward_hive_balance
  OR account_balances.reward_vesting_balance <> _current_account_stats.reward_vesting_balance
  OR account_balances.reward_vesting_hive <> _current_account_stats.reward_vesting_hive
  OR account_balances.delegated_vesting_shares <> _current_account_stats.delegated_vesting_shares
  OR account_balances.received_vesting_shares <> _current_account_stats.received_vesting_shares
  OR account_balances.withdraw_routes <> _current_account_stats.withdraw_routes
  OR account_balances.post_voting_power <> _current_account_stats.post_voting_power
  OR account_balances.posting_rewards <> _current_account_stats.posting_rewards
  OR account_balances.last_post != _current_account_stats.last_post
  OR account_balances.last_root_post != _current_account_stats.last_root_post
  OR account_balances.last_vote_time != _current_account_stats.last_vote_time
  OR account_balances.post_count <> _current_account_stats.post_count;
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_backend.compare_differing_account(_account TEXT)
RETURNS SETOF hafbe_backend.account_type
LANGUAGE 'plpgsql' STABLE
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
