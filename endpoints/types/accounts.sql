SET ROLE hafbe_owner;

-- Account-related types for hafbe_backend

----------------------------------------------------------------------
-- OpenAPI types
----------------------------------------------------------------------

/** openapi:components:schemas
hafbe_backend.auth_with_weight:
  type: array
  x-sql-datatype: JSON
  items:
    anyOf:
      - type: string
      - type: integer
  minItems: 2
  maxItems: 2
 */

/** openapi:components:schemas
hafbe_backend.authority_type:
  type: object
  properties:
    key_auths:
      type: array
      x-sql-datatype: JSON
      items:
        $ref: '#/components/schemas/hafbe_backend.auth_with_weight'
    account_auths:
      type: array
      x-sql-datatype: JSON
      items:
        $ref: '#/components/schemas/hafbe_backend.auth_with_weight'
    weight_threshold:
      type: integer
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.authority_type CASCADE;
CREATE TYPE hafbe_backend.authority_type AS (
    "key_auths" JSON,
    "account_auths" JSON,
    "weight_threshold" INT
);
-- openapi-generated-code-end

----------------------------------------------------------------------

/** openapi:components:schemas
hafbe_backend.account_authority:
  type: object
  properties:
    owner:
      $ref: '#/components/schemas/hafbe_backend.authority_type'
      description: >-
        the most powerful key because it can change any key of an account,
        including the owner key. Ideally it is meant to be stored offline,
        and only used to recover a compromised account
    active:
      $ref: '#/components/schemas/hafbe_backend.authority_type'
      description: >-
        key meant for more sensitive tasks such as transferring funds,
        power up/down transactions, converting Hive Dollars, voting for witnesses,
        updating profile details and avatar, and placing a market order
    posting:
      $ref: '#/components/schemas/hafbe_backend.authority_type'
      description: >-
        key allows accounts to post, comment, edit, vote, reblog
        and follow or mute other accounts
    memo:
      type: string
      description: default key to be used for memo encryption
    witness_signing:
      type: string
      description: >-
        key used by a witness to sign blocks
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.account_authority CASCADE;
CREATE TYPE hafbe_backend.account_authority AS (
    "owner" hafbe_backend.authority_type,
    "active" hafbe_backend.authority_type,
    "posting" hafbe_backend.authority_type,
    "memo" TEXT,
    "witness_signing" TEXT
);
-- openapi-generated-code-end

----------------------------------------------------------------------

/** openapi:components:schemas
hafbe_backend.account:
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
    pending_claimed_accounts:
      type: integer
      description: >-
         pool of prepaid accounts available for user allocation.
         These accounts are pre-registered and can be claimed by users as needed
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
      type: array
      items:
        type: string
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
      type: array
      items:
        type: string
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
DROP TYPE IF EXISTS hafbe_backend.account CASCADE;
CREATE TYPE hafbe_backend.account AS (
    "id" INT,
    "name" TEXT,
    "can_vote" BOOLEAN,
    "mined" BOOLEAN,
    "proxy" TEXT,
    "recovery_account" TEXT,
    "last_account_recovery" TIMESTAMP,
    "created" TIMESTAMP,
    "reputation" INT,
    "pending_claimed_accounts" INT,
    "json_metadata" TEXT,
    "posting_json_metadata" TEXT,
    "profile_image" TEXT,
    "hbd_balance" BIGINT,
    "balance" BIGINT,
    "vesting_shares" TEXT,
    "vesting_balance" BIGINT,
    "hbd_saving_balance" BIGINT,
    "savings_balance" BIGINT,
    "savings_withdraw_requests" INT,
    "reward_hbd_balance" BIGINT,
    "reward_hive_balance" BIGINT,
    "reward_vesting_balance" TEXT,
    "reward_vesting_hive" BIGINT,
    "posting_rewards" TEXT,
    "curation_rewards" TEXT,
    "delegated_vesting_shares" TEXT,
    "received_vesting_shares" TEXT,
    "proxied_vsf_votes" TEXT[],
    "withdrawn" TEXT,
    "vesting_withdraw_rate" TEXT,
    "to_withdraw" TEXT,
    "withdraw_routes" INT,
    "delayed_vests" TEXT,
    "witness_votes" TEXT[],
    "witnesses_voted_for" INT,
    "ops_count" INT,
    "is_witness" BOOLEAN
);
-- openapi-generated-code-end

----------------------------------------------------------------------

/** openapi:components:schemas
hafbe_backend.proxy_power:
  type: object
  properties:
    account:
      type: string
    proxy_date:
      type: string
      format: date-time
    proxied_vests:
      type: string
      description: Own vesting shares plus sum of proxied vesting shares (levels 1–4) decreased by delayed vests
*/
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.proxy_power CASCADE;
CREATE TYPE hafbe_backend.proxy_power AS (
    "account" TEXT,
    "proxy_date" TIMESTAMP,
    "proxied_vests" TEXT
);
-- openapi-generated-code-end

----------------------------------------------------------------------

/** openapi:components:schemas
hafbe_backend.permlink:
  type: object
  properties:
    permlink:
      type: string
      description: >-
        unique post identifier containing post''s title and generated number
    block:
      type: integer
      description: operation block number
    trx_id:
      type: string
      description: hash of the transaction
    timestamp:
      type: string
      format: date-time
      description: creation date
    operation_id:
      type: string
      description: >-
        unique operation identifier with
        an encoded block number and operation type id
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.permlink CASCADE;
CREATE TYPE hafbe_backend.permlink AS (
    "permlink" TEXT,
    "block" INT,
    "trx_id" TEXT,
    "timestamp" TIMESTAMP,
    "operation_id" TEXT
);
-- openapi-generated-code-end

/** openapi:components:schemas
hafbe_backend.permlink_history:
  type: object
  properties:
    total_permlinks:
      type: integer
      description: Total number of permlinks
    total_pages:
      type: integer
      description: Total number of pages
    block_range:
      $ref: '#/components/schemas/hafbe_backend.block_range'
      description: Range of blocks that contains the returned pages
    permlinks_result:
      type: array
      items:
        $ref: '#/components/schemas/hafbe_backend.permlink'
      description: List of permlinks
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.permlink_history CASCADE;
CREATE TYPE hafbe_backend.permlink_history AS (
    "total_permlinks" INT,
    "total_pages" INT,
    "block_range" hafbe_backend.block_range,
    "permlinks_result" hafbe_backend.permlink[]
);
-- openapi-generated-code-end

----------------------------------------------------------------------

/** openapi:components:schemas
hafbe_backend.wallet_stats:
  type: object
  properties:
    date:
      type: string
      format: date-time
      description: end of the time period (capped at current time for the latest partial period)
    new_wallets:
      type: integer
      description: number of new wallets (accounts) created in this period
    total_wallets:
      type: integer
      description: cumulative total wallets on the chain through the end of this period
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.wallet_stats CASCADE;
CREATE TYPE hafbe_backend.wallet_stats AS (
    "date" TIMESTAMP,
    "new_wallets" INT,
    "total_wallets" INT
);
-- openapi-generated-code-end

/** openapi:components:schemas
hafbe_backend.array_of_wallet_stats:
  type: array
  items:
    $ref: '#/components/schemas/hafbe_backend.wallet_stats'
 */

RESET ROLE;
