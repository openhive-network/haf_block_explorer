--ACCOUNT KEYAUTH

DROP TYPE IF EXISTS hafbe_backend.account_keyauth CASCADE;
CREATE TYPE hafbe_backend.account_keyauth AS
(
  key_auth TEXT,
  authority_kind hive.authority_type
);

CREATE OR REPLACE FUNCTION hafbe_backend.get_account_keyauth(_account TEXT)
RETURNS SETOF hafbe_backend.account_keyauth
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
BEGIN

RETURN QUERY SELECT key_auth, authority_kind 
FROM hive.hafbe_app_keyauth 
WHERE account_name= _account 
ORDER BY authority_kind ASC;

END
$$
;

--ACCOUNT SAVINGS

DROP TYPE IF EXISTS hafbe_backend.account_savings CASCADE;
CREATE TYPE hafbe_backend.account_savings AS
(
  hbd_savings numeric,
  hive_savings numeric,
  savings_withdraw_requests INT
);

CREATE OR REPLACE FUNCTION hafbe_backend.get_account_savings(_account INT)
RETURNS hafbe_backend.account_savings
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  __result hafbe_backend.account_savings;
BEGIN

SELECT  
  MAX(CASE WHEN nai = 13 THEN saving_balance END) AS hbd,
  MAX(CASE WHEN nai = 21 THEN saving_balance END) AS hive
INTO __result.hbd_savings, __result.hive_savings
FROM btracker_app.account_savings WHERE account= _account;

SELECT SUM (savings_withdraw_requests) AS total
INTO __result.savings_withdraw_requests
FROM btracker_app.account_savings
WHERE account= _account;

RETURN __result;
END
$$
;

--ACCOUNT REWARDS

DROP TYPE IF EXISTS hafbe_backend.account_rewards CASCADE;
CREATE TYPE hafbe_backend.account_rewards AS
(
  hbd_rewards numeric,
  hive_rewards numeric,
  vests_rewards numeric,
  hive_vesting_rewards numeric
);

CREATE OR REPLACE FUNCTION hafbe_backend.get_account_rewards(_account INT)
RETURNS hafbe_backend.account_rewards
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  __result hafbe_backend.account_rewards;
BEGIN

SELECT  
  MAX(CASE WHEN nai = 13 THEN balance END) AS hbd,
  MAX(CASE WHEN nai = 21 THEN balance END) AS hive,
  MAX(CASE WHEN nai = 37 THEN balance END) AS vests,
  MAX(CASE WHEN nai = 38 THEN balance END) AS vesting_hive
INTO __result
FROM btracker_app.account_rewards WHERE account= _account;

RETURN __result;
END
$$
;

--ACCOUNT METADATA

DROP TYPE IF EXISTS hafbe_backend.json_metadata CASCADE;
CREATE TYPE hafbe_backend.json_metadata AS
(
  json_metadata TEXT,
  posting_json_metadata TEXT
);

CREATE OR REPLACE FUNCTION hafbe_backend.get_json_metadata(_account INT)
RETURNS hafbe_backend.json_metadata
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  __result hafbe_backend.json_metadata;
BEGIN
  SELECT json_metadata, posting_json_metadata 
  INTO __result
  FROM hive.hafbe_app_metadata WHERE account_id= _account;
  RETURN __result;
END
$$
;

--ACCOUNT DELEGATED AND RECEIVED VESTS

DROP TYPE IF EXISTS hafbe_backend.btracker_vests_balance CASCADE;
CREATE TYPE hafbe_backend.btracker_vests_balance AS
(
  delegated_vests BIGINT,
  received_vests BIGINT
);

CREATE OR REPLACE FUNCTION hafbe_backend.get_btracker_vests_balance(_account INT)
RETURNS hafbe_backend.btracker_vests_balance
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _result hafbe_backend.btracker_vests_balance;
BEGIN
  SELECT cv.delegated_vests, cv.received_vests 
  INTO _result
  FROM btracker_app.account_delegations cv WHERE cv.account = _account;

  IF NOT FOUND THEN 
    _result = (0::BIGINT, 0::BIGINT);
  END IF;

  RETURN _result;
END
$$
;

--ACCOUNT CURATION, POSTING REWARDS

DROP TYPE IF EXISTS hafbe_backend.account_info_rewards CASCADE;
CREATE TYPE hafbe_backend.account_info_rewards AS
(
  curation_rewards BIGINT,
  posting_rewards BIGINT
);

CREATE OR REPLACE FUNCTION hafbe_backend.get_account_info_rewards(_account INT)
RETURNS hafbe_backend.account_info_rewards
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _result hafbe_backend.account_info_rewards;
BEGIN
  SELECT cv.curation_rewards, cv.posting_rewards
  INTO _result
  FROM btracker_app.account_info_rewards cv
  WHERE cv.account = _account;

  IF NOT FOUND THEN 
    _result = (0::BIGINT, 0::BIGINT);
  END IF;

  RETURN _result;
END
$$
;

--ACCOUNT WITHDRAWALS

DROP TYPE IF EXISTS hafbe_backend.account_withdraws CASCADE;
CREATE TYPE hafbe_backend.account_withdraws AS
(
  vesting_withdraw_rate numeric,
  to_withdraw numeric,
  withdrawn numeric,
  withdraw_routes INT
);

CREATE OR REPLACE FUNCTION hafbe_backend.get_account_withdraws(_account INT)
RETURNS hafbe_backend.account_withdraws
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  __result hafbe_backend.account_withdraws;
BEGIN
  SELECT vesting_withdraw_rate, to_withdraw, withdrawn, withdraw_routes 
  INTO __result
  FROM btracker_app.account_withdraws WHERE account= _account;
  RETURN __result;
END
$$
;

--ACCOUNT HIVE, HBD, VEST BALANCES

DROP TYPE IF EXISTS hafbe_backend.btracker_account_balance CASCADE;
CREATE TYPE hafbe_backend.btracker_account_balance AS
(
  hbd_balance BIGINT,
  hive_balance BIGINT,
  vesting_shares BIGINT,
  vesting_balance_hive BIGINT,
  post_voting_power_vests BIGINT
);

CREATE OR REPLACE FUNCTION hafbe_backend.get_btracker_account_balance(_account INT)
RETURNS hafbe_backend.btracker_account_balance
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  __result hafbe_backend.btracker_account_balance;
BEGIN

SELECT  
  MAX(CASE WHEN nai = 13 THEN balance END) AS hbd,
  MAX(CASE WHEN nai = 21 THEN balance END) AS hive, 
  MAX(CASE WHEN nai = 37 THEN balance END) AS vest 
INTO __result
FROM btracker_app.current_account_balances WHERE account= _account;

SELECT hive.get_vesting_balance((SELECT num FROM hive.blocks_view ORDER BY num DESC LIMIT 1), __result.vesting_shares) 
INTO __result.vesting_balance_hive;

SELECT (__result.vesting_shares - delegated_vests + received_vests) 
INTO __result.post_voting_power_vests
FROM hafbe_backend.get_btracker_vests_balance(_account);

RETURN __result;

END
$$
;

