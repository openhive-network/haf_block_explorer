SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_backend.compare_accounts()
RETURNS void
LANGUAGE 'plpgsql'
VOLATILE
AS
$$
BEGIN
WITH account_balances AS (
  SELECT 
    name,
    witnesses_voted_for,
    can_vote,
    mined,
    last_account_recovery,
    created,
    proxy,
    last_vote_time
  FROM hafbe_backend.account_balances
)
INSERT INTO hafbe_backend.differing_accounts
SELECT account_balances.name
FROM account_balances
JOIN hafbe_backend.get_account_setof(account_balances.name) AS _current_account_stats
ON _current_account_stats.name = account_balances.name
WHERE 
  account_balances.witnesses_voted_for <> _current_account_stats.witnesses_voted_for

  OR account_balances.can_vote != _current_account_stats.can_vote
  OR account_balances.mined != _current_account_stats.mined
  OR account_balances.last_account_recovery != _current_account_stats.last_account_recovery
  OR account_balances.created != _current_account_stats.created

  OR account_balances.proxy != _current_account_stats.proxy

  OR account_balances.last_vote_time != _current_account_stats.last_vote_time;

END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.compare_differing_account(_account text)
RETURNS SETOF hafbe_backend.account_type -- noqa: LT01
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN QUERY SELECT 
    name,
    witnesses_voted_for,
    can_vote,
    mined,
    last_account_recovery,
    created,
    proxy,
    last_vote_time

  FROM hafbe_backend.account_balances WHERE name = _account
  UNION ALL
SELECT * FROM hafbe_backend.get_account_setof(_account);

END
$$;

RESET ROLE;
