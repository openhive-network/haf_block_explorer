SET ROLE hafbe_owner;

CREATE SCHEMA IF NOT EXISTS hafbe_endpoints AUTHORIZATION hafbe_owner;

-- Account page endpoint
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_account(_account TEXT)
RETURNS hafbe_types.account -- noqa: LT01, CP05
LANGUAGE 'plpgsql'
STABLE
SET JIT = OFF
SET join_collapse_limit = 16
SET from_collapse_limit = 16
AS
$$
DECLARE
  __response_data JSON;
  __json_metadata JSON;
  __posting_json_metadata JSON;
  __profile_image TEXT;
  _account_id INT = hafbe_backend.get_account_id(_account);
BEGIN

-- 2s because this endpoint result is live account parameters and balances 
PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

RETURN (
  SELECT ROW(

    --general
    _account_id,
    _account,
    COALESCE(_result_parameters.can_vote, TRUE),
    COALESCE(_result_parameters.mined, TRUE),
    COALESCE(_result_proxy, ''),
    COALESCE(_result_parameters.recovery_account, ''),
    COALESCE(_result_parameters.last_account_recovery, '1970-01-01T00:00:00'),
    COALESCE(_result_parameters.created,'1970-01-01T00:00:00'), 
    COALESCE(_result_reputation, 0)::INT,

    --metadata
    COALESCE(_result_json_metadata.json_metadata,''),
    COALESCE(_result_json_metadata.posting_json_metadata, ''),
    COALESCE((SELECT hafbe_backend.parse_profile_picture(_result_json_metadata.json_metadata, _result_json_metadata.posting_json_metadata)), ''),

    --balance
    COALESCE(_result_balance.hbd_balance, 0)::BIGINT,
    COALESCE(_result_balance.hive_balance, 0)::BIGINT,
    COALESCE(_result_balance.vesting_shares, 0)::BIGINT,
    COALESCE(_result_balance.vesting_balance_hive, 0)::BIGINT,
    --COALESCE(_result_balance.post_voting_power_vests, 0),

    --saving
    COALESCE(_result_savings.hbd_savings, 0)::BIGINT,
    COALESCE(_result_savings.hive_savings, 0)::BIGINT,
    COALESCE(_result_savings.savings_withdraw_requests, 0),

    --reward
    COALESCE(_result_rewards.hbd_rewards, 0)::BIGINT,
    COALESCE(_result_rewards.hive_rewards, 0)::BIGINT,
    COALESCE(_result_rewards.vests_rewards, 0)::BIGINT,
    COALESCE(_result_rewards.hive_vesting_rewards, 0)::BIGINT,
    COALESCE(_result_curation_posting.posting_rewards, 0)::BIGINT,
    COALESCE(_result_curation_posting.curation_rewards, 0)::BIGINT,

    --received/delegated/proxied
    COALESCE(_result_vest_balance.delegated_vests, 0)::BIGINT,
    COALESCE(_result_vest_balance.received_vests, 0)::BIGINT,
    COALESCE(_result_proxied_votes, '[]'),

    --withdraw
    COALESCE(_result_withdraws.withdrawn, 0)::BIGINT,
    COALESCE(_result_withdraws.vesting_withdraw_rate, 0)::BIGINT,
    COALESCE(_result_withdraws.to_withdraw, 0)::BIGINT,
    COALESCE(_result_withdraws.withdraw_routes, 0)::INT,
    COALESCE(_result_withdraws.delayed_vests, 0)::BIGINT,

    --COALESCE(NULL::TIMESTAMP, '1970-01-01T00:00:00') AS last_post, --- FIXME to be supplemented by new data collection algorithm or removed soon
    --COALESCE(NULL::TIMESTAMP, '1970-01-01T00:00:00') AS last_root_post, --- FIXME to be supplemented by new data collection algorithm or removed soon
    --COALESCE(NULL::INT, 0) AS post_count, --- FIXME to be supplemented by new data collection algorithm or removed soon

    --witness vote
    COALESCE(_result_votes.witness_votes, '[]'),
    COALESCE(_result_votes.witnesses_voted_for, 0)::INT,

    --hidden, shouldn't be shown on account page
    COALESCE(_result_count, 0)::INT,
    EXISTS (SELECT NULL FROM hafbe_app.current_witnesses WHERE witness_id = _account_id)
  )
  FROM 
    btracker_endpoints.get_account_balances(_account_id)      _result_balance,
    btracker_endpoints.get_account_withdraws(_account_id)     _result_withdraws,
    btracker_endpoints.get_account_delegations(_account_id)   _result_vest_balance,
    btracker_endpoints.get_account_rewards(_account_id)       _result_rewards,
    btracker_endpoints.get_account_savings(_account_id)       _result_savings,
    btracker_endpoints.get_account_info_rewards(_account_id)  _result_curation_posting,
    reptracker_endpoints.get_account_reputation(_account_id)  _result_reputation,
    hafbe_backend.get_json_metadata(_account_id)              _result_json_metadata,
    hafbe_backend.get_account_parameters(_account_id)         _result_parameters,
    hafbe_backend.get_account_witness_votes(_account_id)      _result_votes,
    hafbe_backend.get_account_proxy(_account_id)              _result_proxy,
    hafbe_backend.get_account_ops_count(_account_id)          _result_count,
    hafbe_backend.get_account_proxied_vsf_votes(_account_id)  _result_proxied_votes
);

END
$$;


CREATE OR REPLACE FUNCTION hafbe_endpoints.get_account_authority(_account TEXT)
RETURNS hafbe_types.account_authority -- noqa: LT01, CP05
LANGUAGE 'plpgsql'
STABLE
SET JIT = OFF
SET join_collapse_limit = 16
SET from_collapse_limit = 16
AS
$$
BEGIN
RETURN (
  WITH get_account_id AS
  (
    SELECT av.id FROM hive.accounts_view av WHERE av.name = _account
  ),
  authorities AS
  (
    SELECT
      hafbe_backend.get_account_authority(gai.id, 'OWNER') AS owner,
      hafbe_backend.get_account_authority(gai.id, 'ACTIVE') AS active,
      hafbe_backend.get_account_authority(gai.id, 'POSTING') AS posting,   
      hafbe_backend.get_account_memo(gai.id) AS memo,
      hafbe_backend.get_account_witness_signing(gai.id) AS signing
    FROM get_account_id gai
  )
  SELECT ROW(
    to_json(a.owner),
    to_json(a.active),
    to_json(a.posting),
    a.memo,
    a.signing)
  FROM authorities a
);

END
$$;

RESET ROLE;
