SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_backend.compare_accounts()
RETURNS void
LANGUAGE 'plpgsql'
VOLATILE
AS
$$
BEGIN
RAISE NOTICE 'Comparing hafbe parameters with account_dump...';
WITH account_balances AS MATERIALIZED (
  SELECT 
    account_id,
    witnesses_voted_for,
    can_vote,
    mined,
    last_account_recovery,
    created,
    proxy,
    last_vote_time,
    recovery_account
  FROM hafbe_backend.account_balances
),



witnesses_voted_for AS MATERIALIZED (
  SELECT cwvv.voter_id as account_id, COUNT(*)::INT as witnesses_voted_for
  FROM hafbe_app.current_witness_votes cwvv
  GROUP BY cwvv.voter_id
),
account_params AS MATERIALIZED (
  SELECT ap.account as account_id, ap.can_vote, ap.mined, ap.last_account_recovery, ap.created, ap.recovery_account
  FROM hafbe_app.account_parameters ap
),
proxy_account_id AS MATERIALIZED (
  SELECT cap.account_id, cap.proxy_id 
  FROM hafbe_app.current_account_proxies cap
),
selected AS MATERIALIZED (
SELECT
account_balances.account_id,
account_balances.witnesses_voted_for,
account_balances.can_vote,
account_balances.mined,
account_balances.last_account_recovery,
account_balances.created,
account_balances.proxy,
account_balances.recovery_account,

COALESCE(wvf.witnesses_voted_for, 0) AS current_witnesses_voted_for,
COALESCE(ap.can_vote, TRUE) AS current_can_vote,
COALESCE(ap.mined, TRUE) AS current_mined,
COALESCE(ap.last_account_recovery, '1970-01-01T00:00:00') AS current_last_account_recovery,
COALESCE(ap.created, '1970-01-01T00:00:00') AS current_created,
COALESCE(pai.proxy_id, NULL) AS current_proxy,
COALESCE(ap.recovery_account, '') AS current_recovery_account


FROM account_balances
LEFT JOIN witnesses_voted_for wvf ON wvf.account_id = account_balances.account_id
LEFT JOIN account_params ap ON ap.account_id = account_balances.account_id
LEFT JOIN proxy_account_id pai ON pai.account_id = account_balances.account_id
)
INSERT INTO hafbe_backend.differing_accounts
SELECT account_id FROM selected
WHERE account_id > 4 AND (
  witnesses_voted_for != current_witnesses_voted_for
  OR can_vote != current_can_vote
  OR mined != current_mined
  OR last_account_recovery != current_last_account_recovery
  OR created != current_created
  OR proxy != current_proxy
  OR recovery_account != current_recovery_account);

END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.compare_differing_account(_account_id int)
RETURNS SETOF hafbe_backend.account_type -- noqa: LT01
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN QUERY SELECT 
    account_id,
    witnesses_voted_for,
    can_vote,
    mined,
    last_account_recovery,
    created,
    proxy,
    last_vote_time,
    recovery_account

  FROM hafbe_backend.account_balances WHERE account_id = _account_id
  UNION ALL
  SELECT * FROM hafbe_backend.get_account_setof(_account_id);

END
$$;


RESET ROLE;
