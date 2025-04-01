SET ROLE hafbe_owner;

----------------------------------------------------------------------

/** openapi:components:schemas
hafbe_types.authority_type:
  type: object
  properties:
    key_auths:
      type: array
      items:
        type: string
    account_auths:
      type: array
      items:
        type: string
    weight_threshold:
      type: integer
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_types.authority_type CASCADE;
CREATE TYPE hafbe_types.authority_type AS (
    "key_auths" TEXT[],
    "account_auths" TEXT[],
    "weight_threshold" INT
);
-- openapi-generated-code-end

----------------------------------------------------------------------

/** openapi:components:schemas
hafbe_types.account_authority:
  type: object
  properties:
    owner:
      $ref: '#/components/schemas/hafbe_types.authority_type'
      description: >-
        the most powerful key because it can change any key of an account,
        including the owner key. Ideally it is meant to be stored offline,
        and only used to recover a compromised account
    active:
      $ref: '#/components/schemas/hafbe_types.authority_type'
      description: >-
        key meant for more sensitive tasks such as transferring funds,
        power up/down transactions, converting Hive Dollars, voting for witnesses,
        updating profile details and avatar, and placing a market order
    posting:
      $ref: '#/components/schemas/hafbe_types.authority_type'
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
DROP TYPE IF EXISTS hafbe_types.account_authority CASCADE;
CREATE TYPE hafbe_types.account_authority AS (
    "owner" hafbe_types.authority_type,
    "active" hafbe_types.authority_type,
    "posting" hafbe_types.authority_type,
    "memo" TEXT,
    "witness_signing" TEXT
);
-- openapi-generated-code-end

RESET ROLE;
