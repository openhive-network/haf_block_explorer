-- Types used in backend format fuctions

SET ROLE hafbe_owner;

CREATE SCHEMA IF NOT EXISTS hafbe_types AUTHORIZATION hafbe_owner;

----------------------------------------------------------------------

/** openapi:components:schemas
hafbe_types.comment_type:
  type: string
  enum:
    - post
    - comment
    - all
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_types.comment_type CASCADE;
CREATE TYPE hafbe_types.comment_type AS ENUM (
    'post',
    'comment',
    'all'
);
-- openapi-generated-code-end

----------------------------------------------------------------------

/** openapi:components:schemas
hafbe_types.sort_direction:
  type: string
  enum:
    - asc
    - desc
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_types.sort_direction CASCADE;
CREATE TYPE hafbe_types.sort_direction AS ENUM (
    'asc',
    'desc'
);
-- openapi-generated-code-end

----------------------------------------------------------------------

/** openapi:components:schemas
hafbe_types.order_by_votes:
  type: string
  enum:
    - voter
    - vests
    - account_vests
    - proxied_vests
    - timestamp
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_types.order_by_votes CASCADE;
CREATE TYPE hafbe_types.order_by_votes AS ENUM (
    'voter',
    'vests',
    'account_vests',
    'proxied_vests',
    'timestamp'
);
-- openapi-generated-code-end

----------------------------------------------------------------------

/** openapi:components:schemas
hafbe_types.order_by_witness:
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
DROP TYPE IF EXISTS hafbe_types.order_by_witness CASCADE;
CREATE TYPE hafbe_types.order_by_witness AS ENUM (
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

DROP TYPE IF EXISTS hafbe_backend.last_post_vote_time CASCADE; -- noqa: LT01
CREATE TYPE hafbe_backend.last_post_vote_time AS
(
    last_post TIMESTAMP,
    last_root_post TIMESTAMP,
    last_vote_time TIMESTAMP,
    post_count INT
);

----------------------------------------------------------------------

DROP TYPE IF EXISTS hafbe_backend.account_parameters CASCADE; -- noqa: LT01
CREATE TYPE hafbe_backend.account_parameters AS
(
    can_vote BOOLEAN,
    mined BOOLEAN,
    recovery_account TEXT,
    last_account_recovery TIMESTAMP,
    created TIMESTAMP,
    pending_claimed_accounts INT
);

----------------------------------------------------------------------

DROP TYPE IF EXISTS hafbe_backend.account_votes CASCADE; -- noqa: LT01
CREATE TYPE hafbe_backend.account_votes AS
(
    witnesses_voted_for INT,
    witness_votes TEXT[]
);

----------------------------------------------------------------------

DROP TYPE IF EXISTS hafbe_backend.json_metadata CASCADE; -- noqa: LT01
CREATE TYPE hafbe_backend.json_metadata AS
(
    json_metadata TEXT,
    posting_json_metadata TEXT
);

RESET ROLE;
