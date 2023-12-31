-- Types used in backend format fuctions

SET ROLE hafbe_owner;

CREATE SCHEMA IF NOT EXISTS hafbe_types AUTHORIZATION hafbe_owner;


DROP TYPE IF EXISTS hafbe_types.order_is CASCADE; -- noqa: LT01
CREATE TYPE hafbe_types.order_is AS ENUM (
    'asc',
    'desc'
);

DROP TYPE IF EXISTS hafbe_types.group_by CASCADE; -- noqa: LT01
CREATE TYPE hafbe_types.group_by AS ENUM (
    'op_type_id',
    'block_num'
);

DROP TYPE IF EXISTS hafbe_types.order_by_votes CASCADE; -- noqa: LT01
CREATE TYPE hafbe_types.order_by_votes AS ENUM (
    'voter',
    'vests',
    'account_vests',
    'proxied_vests',
    'timestamp'
);

DROP TYPE IF EXISTS hafbe_types.order_by_witness CASCADE; -- noqa: LT01
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
    'feed_age',
    'block_size',
    'signing_key',
    'version'
);

DROP TYPE IF EXISTS hafbe_backend.last_post_vote_time CASCADE; -- noqa: LT01
CREATE TYPE hafbe_backend.last_post_vote_time AS
(
    last_post TIMESTAMP,
    last_root_post TIMESTAMP,
    last_vote_time TIMESTAMP,
    post_count INT
);

DROP TYPE IF EXISTS hafbe_backend.account_parameters CASCADE; -- noqa: LT01
CREATE TYPE hafbe_backend.account_parameters AS
(
    can_vote BOOLEAN,
    mined BOOLEAN,
    recovery_account TEXT,
    last_account_recovery TIMESTAMP,
    created TIMESTAMP
);

DROP TYPE IF EXISTS hafbe_backend.account_votes CASCADE; -- noqa: LT01
CREATE TYPE hafbe_backend.account_votes AS
(
    proxied_vsf_votes JSON,
    witnesses_voted_for INT,
    witness_votes JSON
);

DROP TYPE IF EXISTS hafbe_backend.json_metadata CASCADE; -- noqa: LT01
CREATE TYPE hafbe_backend.json_metadata AS
(
    json_metadata TEXT,
    posting_json_metadata TEXT
);

DROP TYPE IF EXISTS hafbe_backend.operation_body_filter_result CASCADE; -- noqa: LT01
CREATE TYPE hafbe_backend.operation_body_filter_result AS (
    body JSONB,
    id BIGINT,
    is_modified BOOLEAN
);

RESET ROLE;
