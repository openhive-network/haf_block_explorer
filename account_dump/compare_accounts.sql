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
    last_vote_time
  FROM hafbe_backend.account_balances
),
witnesses_voted_for AS MATERIALIZED (
  SELECT cwvv.account as account_id, COUNT(*)::INT as witnesses_voted_for
  FROM hafbe_views.current_witness_votes_view cwvv
  GROUP BY cwvv.account
),
account_params AS MATERIALIZED (
  SELECT ap.account as account_id, ap.can_vote, ap.mined, ap.last_account_recovery, ap.created
  FROM hafbe_app.account_parameters ap
),
proxy_account_id AS MATERIALIZED (
  SELECT cap.account_id, cap.proxy_id 
  FROM hafbe_app.current_account_proxies cap
),
last_vote_time AS MATERIALIZED (
SELECT 
  (SELECT av.id FROM hive.accounts_view av WHERE av.name = vv.voter) as account_id,
  MAX(vv.timestamp) as timestamp
FROM hafbe_views.votes_view vv 
GROUP BY account_id
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
account_balances.last_vote_time,

COALESCE(wvf.witnesses_voted_for, 0) AS current_witnesses_voted_for,
COALESCE(ap.can_vote, TRUE) AS current_can_vote,
COALESCE(ap.mined, TRUE) AS current_mined,
COALESCE(ap.last_account_recovery, '1970-01-01T00:00:00') AS current_last_account_recovery,
COALESCE(ap.created, '1970-01-01T00:00:00') AS current_created,
COALESCE(pai.proxy_id, NULL) AS current_proxy,
COALESCE(lvt.timestamp, '1970-01-01T00:00:00') AS current_last_vote_time

FROM account_balances
LEFT JOIN witnesses_voted_for wvf ON wvf.account_id = account_balances.account_id
LEFT JOIN account_params ap ON ap.account_id = account_balances.account_id
LEFT JOIN proxy_account_id pai ON pai.account_id = account_balances.account_id
LEFT JOIN last_vote_time lvt ON lvt.account_id = account_balances.account_id
)
INSERT INTO hafbe_backend.differing_accounts
SELECT account_id FROM selected
WHERE witnesses_voted_for != current_witnesses_voted_for
  OR can_vote != current_can_vote
  OR mined != current_mined
  OR last_account_recovery != current_last_account_recovery
  OR created != current_created
  OR proxy != current_proxy
  OR last_vote_time != current_last_vote_time;
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
    last_vote_time

  FROM hafbe_backend.account_balances WHERE account_id = _account_id
  UNION ALL
  SELECT * FROM hafbe_backend.get_account_setof(_account_id);

END
$$;


RESET ROLE;
