SET ROLE hafbe_owner;

/** openapi:paths
/accounts/{account-name}:
  get:
    tags:
      - Accounts
    summary: Get information about an account including Hive token balances.
    description: |
      Get account''s balances and parameters

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_account(''blocktrades'');`
      
      REST call example
      * `GET ''https://%1$s/hafbe-api/accounts/blocktrades''`
    operationId: hafbe_endpoints.get_account
    parameters:
      - in: path
        name: account-name
        required: true
        schema:
          type: string
        description: Name of the account
    responses:
      '200':
        description: |
          The account''s parameters
      
          * Returns `hafbe_types.account`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hafbe_types.account'
            example:
              - id: 440
                name: "blocktrades"
                can_vote: true
                mined: true
                proxy: ""
                recovery_account: "steem"
                last_account_recovery: "1970-01-01T00:00:00"
                created: "2016-03-30T00:04:36"
                json_metadata: ""
                posting_json_metadata: ""
                profile_image: ""
                hbd_balance: 77246982
                balance: 29594875
                vesting_shares: "8172549681941451"
                vesting_balance: 2720696229
                hbd_saving_balance: 0
                savings_balance: 0
                savings_withdraw_requests: 0
                reward_hbd_balance: 0
                reward_hive_balance: 0
                reward_vesting_balance: "0"
                reward_vesting_hive: 0
                posting_rewards: "65916519"
                curation_rewards: "196115157"
                delegated_vesting_shares: "0"
                received_vesting_shares: "0"
                proxied_vsf_votes: >-
                  [4983403929606734, 0, 0, 0]
                withdrawn: "804048182205290"
                vesting_withdraw_rate: "80404818220529"
                to_withdraw: "8362101094935031"
                withdraw_routes: 4
                delayed_vests: "0"
                witness_votes: ["steempty","blocktrades","datasecuritynode","steemed","silversteem","witness.svk","joseph","smooth.witness","gtg"]
                witnesses_voted_for: 9
                ops_count: 219867
                is_witness: true
      '404':
        description: No such account in the database
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_account;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_account(
    "account-name" TEXT
)
RETURNS hafbe_types.account 
-- openapi-generated-code-end
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
  _account_id INT = hafbe_backend.get_account_id("account-name");
BEGIN

-- 2s because this endpoint result is live account parameters and balances 
PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

RETURN (
  SELECT ROW(

    --general
    _account_id,
    "account-name",
    COALESCE(_result_parameters.can_vote, TRUE),
    COALESCE(_result_parameters.mined, TRUE),
    COALESCE(_result_proxy, ''),
    COALESCE(_result_parameters.recovery_account, ''),
    COALESCE(_result_parameters.last_account_recovery, '1970-01-01T00:00:00'),
    COALESCE(_result_parameters.created,'1970-01-01T00:00:00'), 

    --metadata
    COALESCE(_result_json_metadata.json_metadata,''),
    COALESCE(_result_json_metadata.posting_json_metadata, ''),
    COALESCE((SELECT hafbe_backend.parse_profile_picture(_result_json_metadata.json_metadata, _result_json_metadata.posting_json_metadata)), ''),

    --balance
    COALESCE(_result_balance.hbd_balance, 0)::BIGINT,
    COALESCE(_result_balance.hive_balance, 0)::BIGINT,
    COALESCE(_result_balance.vesting_shares, '0')::TEXT,
    COALESCE(_result_balance.vesting_balance_hive, 0)::BIGINT,
    --COALESCE(_result_balance.post_voting_power_vests, 0),

    --saving
    COALESCE(_result_balance.hbd_savings, 0)::BIGINT,
    COALESCE(_result_balance.hive_savings, 0)::BIGINT,
    COALESCE(_result_balance.savings_withdraw_requests, 0),

    --reward
    COALESCE(_result_balance.hbd_rewards, 0)::BIGINT,
    COALESCE(_result_balance.hive_rewards, 0)::BIGINT,
    COALESCE(_result_balance.vests_rewards, '0')::TEXT,
    COALESCE(_result_balance.hive_vesting_rewards, 0)::BIGINT,
    COALESCE(_result_balance.posting_rewards, '0')::TEXT,
    COALESCE(_result_balance.curation_rewards, '0')::TEXT,

    --received/delegated/proxied
    COALESCE(_result_balance.delegated_vests, '0')::TEXT,
    COALESCE(_result_balance.received_vests, '0')::TEXT,
    COALESCE(_result_proxied_votes, '[]'),

    --withdraw
    COALESCE(_result_balance.withdrawn, '0')::TEXT,
    COALESCE(_result_balance.vesting_withdraw_rate, '0')::TEXT,
    COALESCE(_result_balance.to_withdraw, '0')::TEXT,
    COALESCE(_result_balance.withdraw_routes, 0)::INT,
    COALESCE(_result_balance.delayed_vests, '0')::TEXT,

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
    btracker_endpoints.get_account_balances("account-name")      _result_balance,
    hafbe_backend.get_json_metadata(_account_id)              _result_json_metadata,
    hafbe_backend.get_account_parameters(_account_id)         _result_parameters,
    hafbe_backend.get_account_witness_votes(_account_id)      _result_votes,
    hafbe_backend.get_account_proxy(_account_id)              _result_proxy,
    hafbe_backend.get_account_ops_count(_account_id)          _result_count,
    hafbe_backend.get_account_proxied_vsf_votes(_account_id)  _result_proxied_votes
);

END
$$;

RESET ROLE;
