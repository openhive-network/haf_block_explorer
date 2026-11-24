SET ROLE hafbe_owner;

-- Proposal-related types for hafbe_backend

----------------------------------------------------------------------

/** openapi:components:schemas
hafbe_backend.proposal_votes_change_window:
  type: object
  x-sql-datatype: JSON
  properties:
    total:
      type: string
      description: >-
        the change in the proposal''s votes over the window, in VESTS: the sum
        of the cause fields below
    voters:
      type: integer
      description: the number of the proposal''s voters whose events moved its votes
    funded_start:
      type: boolean
      nullable: true
      description: >-
        whether the proposal ranked above the return proposal (id 0) at the
        window start, with more votes than it: hived pays the proposals above
        it, as far as the budget goes. For a proposal not started yet, where it
        would have stood. null for the return proposal itself and for a
        proposal that has ended
    gap_start:
      type: string
      nullable: true
      description: >-
        the proposal''s votes minus the return proposal''s at the window start,
        in VESTS (the current gap is this plus total minus the return proposal''s
        total); null where funded_start is
    votes_cast:
      type: string
      description: votes cast, each at the voter''s weight when it voted, in VESTS
    votes_removed:
      type: string
      description: votes removed, each at the voter''s weight then, in VESTS
    power_down:
      type: string
      description: power-down withdrawals of the voters and their proxies, in VESTS
    power_up:
      type: string
      description: power-ups finishing their 30-day voting delay, in VESTS
    producer_reward:
      type: string
      description: block producer rewards paid in VESTS
    claimed_reward:
      type: string
      description: author and curation rewards claimed in VESTS
    proxy:
      type: string
      description: >-
        weight moved by proxies being set, changed or cleared: a voter that
        sets a proxy stops counting for its proposals until it clears it, in
        VESTS
    expired:
      type: string
      description: >-
        votes and proxies removed after a year without governance activity,
        in VESTS
    declined:
      type: string
      description: votes and proxies removed by declining voting rights, in VESTS
*/

/** openapi:components:schemas
hafbe_backend.proposal_votes_change_breakdown:
  type: object
  x-sql-datatype: JSON
  properties:
    as_of_block:
      type: integer
      description: the last block processed when the breakdown was refreshed (about every 100 blocks, and at the first block of each UTC day)
    today:
      $ref: '#/components/schemas/hafbe_backend.proposal_votes_change_window'
      description: the change since 00:00 UTC
    7d:
      $ref: '#/components/schemas/hafbe_backend.proposal_votes_change_window'
      description: the change over the 7 days up to as_of_block
*/

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
    votes_change_breakdown:
      $ref: '#/components/schemas/hafbe_backend.proposal_votes_change_breakdown'
      x-sql-datatype: JSON
      description: >-
        the change in the proposal''s votes broken down by cause, and its gap
        to the return proposal at each window start, today and over 7 days;
        null until the first refresh
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
    "status" TEXT,
    "votes_change_breakdown" JSON
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
    direct_vests:
      type: string
      description: this voter''s own governance VESTS (account_vests) at last cache refresh, independent of any proxy
    proxied_vests:
      type: string
      description: VESTS from accounts that have proxied their governance to this voter
    proxy:
      type: string
      description: name of the governance proxy this voter has set (empty string if none)
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
    "direct_vests" TEXT,
    "proxied_vests" TEXT,
    "proxy" TEXT,
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
    voter_vests:
      type: string
      description: >-
        effective governance VESTS carried by this voter''s direct proposal vote
        (0 if the voter currently has a proxy set — their stake counts through the
        proxy, and hived''s proposal totals exclude them).
        NOTE: this is the voter''s CURRENT stake, not the stake they held at the block
        of this historical vote event — no point-in-time vesting snapshot is kept.
    direct_vests:
      type: string
      description: >-
        this voter''s own governance VESTS (account_vests), independent of any proxy.
        Never zeroed, so the voter''s real stake stays visible when voter_vests is 0.
    proxied_vests:
      type: string
      description: VESTS from accounts that have proxied their governance to this voter
    proxy:
      type: string
      description: >-
        name of the governance proxy this voter has set (empty string if none).
        Whenever this field is non-empty, voter_vests is 0. The converse does NOT hold:
        a voter who simply holds no VESTS also reports 0, with an empty proxy.
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
    "voter_vests" TEXT,
    "direct_vests" TEXT,
    "proxied_vests" TEXT,
    "proxy" TEXT,
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
