SET ROLE hafbe_owner;

-- Enum types used in hafbe_backend

----------------------------------------------------------------------

/** openapi:components:schemas
hafbe_backend.comment_type:
  type: string
  enum:
    - post
    - comment
    - all
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.comment_type CASCADE;
CREATE TYPE hafbe_backend.comment_type AS ENUM (
    'post',
    'comment',
    'all'
);
-- openapi-generated-code-end

----------------------------------------------------------------------

/** openapi:components:schemas
hafbe_backend.sort_direction:
  type: string
  enum:
    - asc
    - desc
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.sort_direction CASCADE;
CREATE TYPE hafbe_backend.sort_direction AS ENUM (
    'asc',
    'desc'
);
-- openapi-generated-code-end

----------------------------------------------------------------------

/** openapi:components:schemas
hafbe_backend.order_by_votes:
  type: string
  enum:
    - voter
    - vests
    - account_vests
    - proxied_vests
    - timestamp
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.order_by_votes CASCADE;
CREATE TYPE hafbe_backend.order_by_votes AS ENUM (
    'voter',
    'vests',
    'account_vests',
    'proxied_vests',
    'timestamp'
);
-- openapi-generated-code-end

----------------------------------------------------------------------

/** openapi:components:schemas
hafbe_backend.order_by_proxy:
  type: string
  enum:
    - account
    - proxy_date
    - proxied_vests
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.order_by_proxy CASCADE;
CREATE TYPE hafbe_backend.order_by_proxy AS ENUM (
    'account',
    'proxy_date',
    'proxied_vests'
);
-- openapi-generated-code-end

----------------------------------------------------------------------

/** openapi:components:schemas
hafbe_backend.order_by_witness:
  type: string
  enum:
    - witness
    - rank
    - url
    - votes
    - votes_daily_change
    - voters_num
    - voters_num_daily_change
    - price_feed
    - bias
    - block_size
    - signing_key
    - version
    - feed_updated_at
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.order_by_witness CASCADE;
CREATE TYPE hafbe_backend.order_by_witness AS ENUM (
    'witness',
    'rank',
    'url',
    'votes',
    'votes_daily_change',
    'voters_num',
    'voters_num_daily_change',
    'price_feed',
    'bias',
    'block_size',
    'signing_key',
    'version',
    'feed_updated_at'
);
-- openapi-generated-code-end

----------------------------------------------------------------------

/** openapi:components:schemas
hafbe_backend.order_by_proposal:
  type: string
  enum:
    - by_creator
    - by_start_date
    - by_end_date
    - by_total_votes
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.order_by_proposal CASCADE;
CREATE TYPE hafbe_backend.order_by_proposal AS ENUM (
    'by_creator',
    'by_start_date',
    'by_end_date',
    'by_total_votes'
);
-- openapi-generated-code-end

----------------------------------------------------------------------

/** openapi:components:schemas
hafbe_backend.order_by_proposal_vote:
  type: string
  enum:
    - by_voter_proposal
    - by_proposal_voter
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.order_by_proposal_vote CASCADE;
CREATE TYPE hafbe_backend.order_by_proposal_vote AS ENUM (
    'by_voter_proposal',
    'by_proposal_voter'
);
-- openapi-generated-code-end

----------------------------------------------------------------------

/** openapi:components:schemas
hafbe_backend.proposal_status:
  type: string
  enum:
    - all
    - active
    - inactive
    - expired
    - votable
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.proposal_status CASCADE;
CREATE TYPE hafbe_backend.proposal_status AS ENUM (
    'all',
    'active',
    'inactive',
    'expired',
    'votable'
);
-- openapi-generated-code-end

----------------------------------------------------------------------

/** openapi:components:schemas
hafbe_backend.granularity:
  type: string
  enum:
    - daily
    - monthly
    - yearly
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.granularity CASCADE;
CREATE TYPE hafbe_backend.granularity AS ENUM (
    'daily',
    'monthly',
    'yearly'
);
-- openapi-generated-code-end

RESET ROLE;
