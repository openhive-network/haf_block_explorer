SET ROLE hafbe_owner;

DO $$
BEGIN

CREATE SCHEMA hafbe_backend AUTHORIZATION hafbe_owner;

CREATE TABLE IF NOT EXISTS hafbe_backend.account_balances (
    account_id INT,
    witnesses_voted_for INT DEFAULT 0,
    can_vote BOOLEAN DEFAULT TRUE,
    mined BOOLEAN DEFAULT TRUE,
    last_account_recovery TIMESTAMP DEFAULT '1970-01-01T00:00:00',
    created TIMESTAMP DEFAULT '1970-01-01T00:00:00',
    proxy INT DEFAULT NULL,
    last_vote_time TIMESTAMP DEFAULT '1970-01-01T00:00:00',
    recovery_account TEXT DEFAULT '',


CONSTRAINT pk_account_balances_comparison PRIMARY KEY (account_id)
);

CREATE TABLE IF NOT EXISTS hafbe_backend.witness_props (
  witness_id INT,
  url TEXT DEFAULT '',                    -- url
  vests BIGINT DEFAULT 0,                 -- votes
  missed_blocks INT DEFAULT 0,            -- total_missed
  last_confirmed_block_num INT DEFAULT 0, -- last_confirmed_block_num
  signing_key TEXT DEFAULT '',            -- signing_key
  version TEXT DEFAULT '',                -- running_version

  account_creation_fee INT DEFAULT 0,                      -- account_creation_fee
  block_size INT DEFAULT 0,                                -- maximum_block_size
  hbd_interest_rate INT DEFAULT 0,                         -- hbd_interest_rate
  price_feed NUMERIC DEFAULT 0,                                -- hbd_exchange_rate_base
  feed_updated_at TIMESTAMP DEFAULT '1970-01-01T00:00:00', -- last_hbd_exchange_update

  CONSTRAINT pk_account_witnesses PRIMARY KEY (witness_id)
);

CREATE TABLE IF NOT EXISTS hafbe_backend.differing_accounts (
  account_id INT
);

CREATE TABLE IF NOT EXISTS hafbe_backend.differing_witnesses (
  witness_id INT
);

EXCEPTION WHEN duplicate_schema THEN RAISE NOTICE '%, skipping', SQLERRM USING ERRCODE = SQLSTATE;

END
$$;

RESET ROLE;
