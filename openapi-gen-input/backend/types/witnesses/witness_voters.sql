SET ROLE hafbe_owner;

/** openapi:components:schemas
hafbe_types.witness_voter:
  type: object
  properties:
    voter_name:
      type: string
      description: account name of the voter
    vests:
      type: string
      description: number of vests this voter is directly voting with
    account_vests:
      type: string
      description: >-
        number of vests in the voter''s account.  if some vests are
        delegated, they will not be counted in voting
    proxied_vests:
      type: string
      description: the number of vests proxied to this account
    timestamp:
      type: string
      format: date-time
      description: the time this account last changed its voting power
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_types.witness_voter CASCADE;
CREATE TYPE hafbe_types.witness_voter AS (
    "voter_name" TEXT,
    "vests" TEXT,
    "account_vests" TEXT,
    "proxied_vests" TEXT,
    "timestamp" TIMESTAMP
);
-- openapi-generated-code-end

/** openapi:components:schemas
hafbe_types.array_of_witness_voters:
  type: array
  items:
    $ref: '#/components/schemas/hafbe_types.witness_voter'
 */

RESET ROLE;
