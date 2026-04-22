SET ROLE hafbe_owner;

-- Proposal-related types for hafbe_backend

----------------------------------------------------------------------

/** openapi:components:schemas
hafbe_backend.proposal_votes_history_record:
  type: object
  properties:
    voter_name:
      type: string
      description: account name of the voter
    approve:
      type: boolean
      description: whether the voter approved or withdrew approval of the proposal
    timestamp:
      type: string
      format: date-time
      description: the time of the vote change
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.proposal_votes_history_record CASCADE;
CREATE TYPE hafbe_backend.proposal_votes_history_record AS (
    "voter_name" TEXT,
    "approve" BOOLEAN,
    "timestamp" TIMESTAMP
);
-- openapi-generated-code-end

/** openapi:components:schemas
hafbe_backend.proposal_votes_history:
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
        $ref: '#/components/schemas/hafbe_backend.proposal_votes_history_record'
      description: List of proposal vote changes
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.proposal_votes_history CASCADE;
CREATE TYPE hafbe_backend.proposal_votes_history AS (
    "total_votes" INT,
    "total_pages" INT,
    "votes_history" hafbe_backend.proposal_votes_history_record[]
);
-- openapi-generated-code-end

RESET ROLE;
