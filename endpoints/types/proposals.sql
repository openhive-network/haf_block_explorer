SET ROLE hafbe_owner;

-- Proposal-related types for hafbe_backend

----------------------------------------------------------------------

/** openapi:components:schemas
hafbe_backend.proposal:
  type: object
  properties:
    id:
      type: integer
      description: proposal id assigned by hived at creation (mirrors condenser_api `id`)
    proposal_id:
      type: integer
      description: proposal id assigned by hived at creation (mirrors condenser_api `proposal_id` — duplicate of `id` for client parity)
    creator:
      type: string
      description: account that created the proposal
    receiver:
      type: string
      description: account that receives the daily payout
    start_date:
      type: string
      format: date-time
      description: when the proposal becomes payable
    end_date:
      type: string
      format: date-time
      description: when the proposal stops being payable
    daily_pay:
      type: string
      description: requested daily HBD payout in precision-3 units (milli-HBD)
    subject:
      type: string
      description: human-readable proposal subject
    permlink:
      type: string
      description: permlink pointing to the proposal discussion post
    total_votes:
      type: string
      description: stake-weighted total approval in VESTS, summed across direct (non-proxied) voters
    voters_num:
      type: integer
      description: number of direct (non-proxied) approving voters
    paid_amount:
      type: string
      description: cumulative HBD paid to this proposal so far in precision-3 units (milli-HBD)
    status:
      type: string
      enum: [active, inactive, expired]
      description: |
        Current proposal status computed from start_date/end_date relative to
        the HAFBE processed head block. Removed proposals are filtered out
        upstream by every status filter (including `all`) and never appear in
        the response, so this enum has only the three live states.
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.proposal CASCADE;
CREATE TYPE hafbe_backend.proposal AS (
    "id" INT,
    "proposal_id" INT,
    "creator" TEXT,
    "receiver" TEXT,
    "start_date" TIMESTAMP,
    "end_date" TIMESTAMP,
    "daily_pay" TEXT,
    "subject" TEXT,
    "permlink" TEXT,
    "total_votes" TEXT,
    "voters_num" INT,
    "paid_amount" TEXT,
    "status" TEXT
);
-- openapi-generated-code-end

/** openapi:components:schemas
hafbe_backend.proposals_return:
  type: object
  properties:
    total_proposals:
      type: integer
      description: Total number of proposals matching the status filter
    total_pages:
      type: integer
      description: Total number of pages
    proposals:
      type: array
      items:
        $ref: '#/components/schemas/hafbe_backend.proposal'
      description: List of proposals
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.proposals_return CASCADE;
CREATE TYPE hafbe_backend.proposals_return AS (
    "total_proposals" INT,
    "total_pages" INT,
    "proposals" hafbe_backend.proposal[]
);
-- openapi-generated-code-end

----------------------------------------------------------------------

/** openapi:components:schemas
hafbe_backend.proposal_vote:
  type: object
  properties:
    voter_name:
      type: string
      description: account name of the voter
    proposal:
      $ref: '#/components/schemas/hafbe_backend.proposal'
      description: nested proposal object — mirrors condenser_api `ProposalVote.proposal` so the front end can display the proposal alongside the vote without a second request
    voter_vests:
      type: string
      description: effective governance VESTS for this voter at last cache refresh (0 if voter currently has a proxy set)
    timestamp:
      type: string
      format: date-time
      description: block timestamp at which this active vote was last (re)cast
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.proposal_vote CASCADE;
CREATE TYPE hafbe_backend.proposal_vote AS (
    "voter_name" TEXT,
    "proposal" hafbe_backend.proposal,
    "voter_vests" TEXT,
    "timestamp" TIMESTAMP
);
-- openapi-generated-code-end

/** openapi:components:schemas
hafbe_backend.proposal_votes_return:
  type: object
  properties:
    total_votes:
      type: integer
      description: Total number of active proposal votes matching the filter
    total_pages:
      type: integer
      description: Total number of pages
    votes:
      type: array
      items:
        $ref: '#/components/schemas/hafbe_backend.proposal_vote'
      description: List of current active proposal votes
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.proposal_votes_return CASCADE;
CREATE TYPE hafbe_backend.proposal_votes_return AS (
    "total_votes" INT,
    "total_pages" INT,
    "votes" hafbe_backend.proposal_vote[]
);
-- openapi-generated-code-end

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
