SET ROLE hafbe_owner;

/** openapi:components:schemas
hafbe_types.account_authority:
  type: object
  properties:
    owner:
      type: string
      x-sql-datatype: JSON
      description: >-
        the most powerful key because it can change any key of an account,
        including the owner key. Ideally it is meant to be stored offline,
        and only used to recover a compromised account
    active:
      type: string
      x-sql-datatype: JSON
      description: >-
        key meant for more sensitive tasks such as transferring funds,
        power up/down transactions, converting Hive Dollars, voting for witnesses,
        updating profile details and avatar, and placing a market order
    posting:
      type: string
      x-sql-datatype: JSON
      description: >-
        key allows accounts to post, comment, edit, vote, reblog
        and follow or mute other accounts
    memo:
      type: string
      description: currently the memo key is not used
    witness_signing:
      type: string
      description: >-
        key used to sign block by witness
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_types.account_authority CASCADE;
CREATE TYPE hafbe_types.account_authority AS (
    "owner" JSON,
    "active" JSON,
    "posting" JSON,
    "memo" TEXT,
    "witness_signing" TEXT
);
-- openapi-generated-code-end

RESET ROLE;
