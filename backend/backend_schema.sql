SET ROLE hafbe_owner;

DO $$
BEGIN

CREATE SCHEMA hafbe_backend AUTHORIZATION hafbe_owner;

CREATE TABLE IF NOT EXISTS hafbe_backend.account_balances (
    name TEXT,
    witnesses_voted_for INT DEFAULT 0,
    can_vote BOOLEAN DEFAULT TRUE,
    mined BOOLEAN DEFAULT TRUE,
    recovery_account TEXT DEFAULT 'steem',
    last_account_recovery TIMESTAMP DEFAULT '1970-01-01T00:00:00',
    created TIMESTAMP DEFAULT '1970-01-01T00:00:00',
    proxy TEXT DEFAULT '',
    last_post TIMESTAMP DEFAULT '1970-01-01T00:00:00',
    last_root_post TIMESTAMP DEFAULT '1970-01-01T00:00:00',
    last_vote_time TIMESTAMP DEFAULT '1970-01-01T00:00:00',
    post_count INT DEFAULT 0,

CONSTRAINT pk_account_balances_comparison PRIMARY KEY (name)
);

CREATE TABLE IF NOT EXISTS hafbe_backend.differing_accounts (
  account_name TEXT
);

EXCEPTION WHEN duplicate_schema THEN RAISE NOTICE '%, skipping', SQLERRM USING ERRCODE = SQLSTATE;

END
$$
;

RESET ROLE;
