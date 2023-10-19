SET ROLE hafbe_owner;

CREATE SCHEMA IF NOT EXISTS hafbe_types AUTHORIZATION hafbe_owner;

DROP TYPE IF EXISTS hafbe_types.order_is CASCADE;
CREATE TYPE hafbe_types.order_is AS ENUM(
  'asc', 
  'desc'
);

DROP TYPE IF EXISTS hafbe_types.order_by_votes CASCADE;
CREATE TYPE hafbe_types.order_by_votes AS ENUM(
  'voter', 
  'vests',
  'account_vests',
  'proxied_vests',
  'timestamp'
);

DROP TYPE IF EXISTS hafbe_types.order_by_witness CASCADE;
CREATE TYPE hafbe_types.order_by_witness AS ENUM(
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

