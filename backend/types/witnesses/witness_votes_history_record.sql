SET ROLE hafbe_owner;

/** openapi:components:schemas
hafbe_types.witness_votes_history_record:
  type: object
  properties:
    voter:
      type: string
      description: account name of the voter
    approve:
      type: boolean
      description: whether the voter approved or rejected the witness
    vests:
      type: string
      description: number of vests this voter is directly voting with
    votes_hive_power:
      type: integer
      x-sql-datatype: BIGINT
      description: >-
        number of vests this voter is directly voting with, expressed in
        HIVE power, at the current ratio
    account_vests:
      type: string
      description: >-
        number of vests in the voter''s account.  if some vests are
        delegated, they will not be counted in voting
    account_hive_power:
      type: integer
      x-sql-datatype: BIGINT
      description: >-
        number of vests in the voter''s account, expressed in HIVE power, at
        the current ratio.  if some vests are delegated, they will not be
        counted in voting
    proxied_vests:
      type: string
      description: the number of vests proxied to this account
    proxied_hive_power:
      type: integer
      x-sql-datatype: BIGINT
      description: >-
        the number of vests proxied to this account expressed in HIVE power,
        at the current ratio
    timestamp:
      type: string
      format: date-time
      description: the time of the vote change
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_types.witness_votes_history_record CASCADE;
CREATE TYPE hafbe_types.witness_votes_history_record AS (
    "voter" TEXT,
    "approve" BOOLEAN,
    "vests" TEXT,
    "votes_hive_power" BIGINT,
    "account_vests" TEXT,
    "account_hive_power" BIGINT,
    "proxied_vests" TEXT,
    "proxied_hive_power" BIGINT,
    "timestamp" TIMESTAMP
);
-- openapi-generated-code-end

/** openapi:components:schemas
hafbe_types.array_of_witness_vote_history_records:
  type: array
  items:
    $ref: '#/components/schemas/hafbe_types.witness_votes_history_record'
 */

RESET ROLE;
