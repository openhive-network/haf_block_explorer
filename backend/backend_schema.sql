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


CONSTRAINT pk_account_balances_comparison PRIMARY KEY (account_id)
);

CREATE TABLE IF NOT EXISTS hafbe_backend.differing_accounts (
  account_id INT
);

EXCEPTION WHEN duplicate_schema THEN RAISE NOTICE '%, skipping', SQLERRM USING ERRCODE = SQLSTATE;

END
$$;

RESET ROLE;
