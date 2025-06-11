SET ROLE hafbe_owner;

/** openapi:components:schemas
hafbe_types.witness_votes_history_record:
  type: object
  properties:
    voter_name:
      type: string
      description: account name of the voter
    approve:
      type: boolean
      description: whether the voter approved or rejected the witness
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
      description: the time of the vote change
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_types.witness_votes_history_record CASCADE;
CREATE TYPE hafbe_types.witness_votes_history_record AS (
    "voter_name" TEXT,
    "approve" BOOLEAN,
    "vests" TEXT,
    "account_vests" TEXT,
    "proxied_vests" TEXT,
    "timestamp" TIMESTAMP
);
-- openapi-generated-code-end

/** openapi:components:schemas
hafbe_types.witness_votes_history:
  type: object
  properties:
    total_votes:
      type: integer
      description: Total number of votes
    total_pages:
      type: integer
      description: Total number of pages
    votes_history:
      type: array
      items:
        $ref: '#/components/schemas/hafbe_types.witness_votes_history_record'
      description: List of witness votes
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_types.witness_votes_history CASCADE;
CREATE TYPE hafbe_types.witness_votes_history AS (
    "total_votes" INT,
    "total_pages" INT,
    "votes_history" hafbe_types.witness_votes_history_record[]
);
-- openapi-generated-code-end

RESET ROLE;
