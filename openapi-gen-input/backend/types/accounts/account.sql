SET ROLE hafbe_owner;

/** openapi:components:schemas
hafbe_types.account:
  type: object
  properties:
    id:
      type: integer
      description: account''s identification number
    name:
      type: string
      description: account''s name
    can_vote:
      type: boolean
      description: information whether the account can vote or not
    mined:
      type: boolean
      description: information whether made a prove of work
    proxy:
      type: string
      description: an account to which the account has designated as its proxy
    recovery_account:
      type: string
      description: an account to which the account has designated as its recovery account
    last_account_recovery:
      type: string
      format: date-time
      description: time when the last account recovery was performed
    created:
      type: string
      format: date-time
      description: date of account creation
    reputation:
      type: integer
      description: >-
        numerical rating of the user 
        based on upvotes and downvotes on user''s posts
    json_metadata:
      type: string
      description: parameter encompasses personalized profile information
    posting_json_metadata:
      type: string
      description: parameter encompasses personalized profile information
    profile_image:
      type: string
      description: url to profile image
    hbd_balance:
      type: integer
      x-sql-datatype: BIGINT
      description: number of HIVE backed dollars the account has
    balance:
      type: integer
      x-sql-datatype: BIGINT
      description: account''s HIVE balance
    vesting_shares:
      type: string
      description: account''s VEST balance
    vesting_balance:
      type: integer
      x-sql-datatype: BIGINT
      description: >- 
        the VEST balance, presented in HIVE, 
        is calculated based on the current HIVE price
    hbd_saving_balance:
      type: integer
      x-sql-datatype: BIGINT
      description: saving balance of HIVE backed dollars
    savings_balance:
      type: integer
      x-sql-datatype: BIGINT
      description: HIVE saving balance
    savings_withdraw_requests:
      type: integer
      description: >-
        number representing how many payouts are pending 
        from user''s saving balance 
    reward_hbd_balance:
      type: integer
      x-sql-datatype: BIGINT
      description: >-
        not yet claimed HIVE backed dollars 
        stored in hbd reward balance
    reward_hive_balance:
      type: integer
      x-sql-datatype: BIGINT
      description: >-
        not yet claimed HIVE 
        stored in hive reward balance
    reward_vesting_balance:
      type: string
      description: >-
        not yet claimed VESTS 
        stored in vest reward balance
    reward_vesting_hive:
      type: integer
      x-sql-datatype: BIGINT
      description: >-
        the reward vesting balance, denominated in HIVE, 
        is determined by the prevailing HIVE price at the time of reward reception
    posting_rewards:
      type: string
      description: rewards obtained by posting and commenting expressed in VEST
    curation_rewards:
      type: string
      description: curator''s reward expressed in VEST
    delegated_vesting_shares:
      type: string
      description: >-
        VESTS delegated to another user, 
        account''s power is lowered by delegated VESTS
    received_vesting_shares:
      type: string
      description: >-
        VESTS received from another user, 
        account''s power is increased by received VESTS
    proxied_vsf_votes:
      type: string
      x-sql-datatype: JSON
      description: >-
        recursive proxy of VESTS 
    withdrawn:
      type: string
      description: the total VESTS already withdrawn from active withdrawals
    vesting_withdraw_rate:
      type: string
      description: >-
        received until the withdrawal is complete, 
        with each installment amounting to 1/13 of the withdrawn total
    to_withdraw:
      type: string
      description: the remaining total VESTS needed to complete withdrawals
    withdraw_routes:
      type: integer
      description: list of account receiving the part of a withdrawal
    delayed_vests:
      type: string
      description: blocked VESTS by a withdrawal
    witness_votes:
      type: string
      x-sql-datatype: JSON
      description: the roster of witnesses voted by the account
    witnesses_voted_for:
      type: integer
      description: count of witness_votes
    ops_count:
      type: integer
      description: the number of operations performed by the account 
    is_witness:
      type: boolean
      description: whether account is a witness
 */
-- openapi-generated-code-begin
-- openapi-generated-code-end

RESET ROLE;
