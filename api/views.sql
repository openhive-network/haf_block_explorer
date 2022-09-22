DROP SCHEMA IF EXISTS hafbe_views CASCADE;

CREATE SCHEMA hafbe_views;

DROP VIEW IF EXISTS hafbe_views.recursively_proxied_vests_view;
CREATE VIEW hafbe_views.recursively_proxied_vests_view AS
SELECT
  proxies.voter_id,
  SUM(proxied.vests) AS proxied_vests
FROM (
  SELECT
    prox1.proxy_id AS voter_id,
    prox1.account_id AS voters_proxies,
    prox2.account_id AS proxies_of_voters_proxies,
    prox3.account_id AS proxies_of_proxies1,
    prox4.account_id AS proxies_of_proxies2,
    prox5.account_id AS proxies_of_proxies3
  FROM hafbe_app.current_account_proxies prox1

  LEFT JOIN (
    SELECT account_id, proxy_id
    FROM hafbe_app.current_account_proxies
    WHERE proxy = true
  ) prox2 ON prox2.proxy_id = prox1.account_id

  LEFT JOIN (
    SELECT account_id, proxy_id
    FROM hafbe_app.current_account_proxies
    WHERE proxy = true
  ) prox3 ON prox3.proxy_id = prox2.account_id

  LEFT JOIN (
    SELECT account_id, proxy_id
    FROM hafbe_app.current_account_proxies
    WHERE proxy = true
  ) prox4 ON prox4.proxy_id = prox3.account_id

  LEFT JOIN (
    SELECT account_id, proxy_id
    FROM hafbe_app.current_account_proxies
    WHERE proxy = true
  ) prox5 ON prox5.proxy_id = prox4.account_id

  WHERE prox1.proxy = TRUE
) proxies

CROSS JOIN LATERAL (
  VALUES (voters_proxies), (proxies_of_voters_proxies), (proxies_of_proxies1), (proxies_of_proxies2), (proxies_of_proxies3)
) AS unpivot(account_id)

JOIN LATERAL (
  SELECT vests, account_id
  FROM hafbe_app.account_vests
  WHERE account_id = unpivot.account_id
) proxied ON proxied.account_id = unpivot.account_id

WHERE unpivot.account_id IS NOT NULL
GROUP BY proxies.voter_id
;

DROP VIEW IF EXISTS hafbe_views.voters_stats_view;
CREATE VIEW hafbe_views.voters_stats_view AS
SELECT
  cwv.witness_id, cwv.voter_id, cwv.timestamp,
  COALESCE(account.vests, 0)::NUMERIC AS account_vests,
  COALESCE(rpv.proxied_vests, 0) AS proxied_vests
FROM hafbe_app.current_witness_votes cwv

LEFT JOIN (
  SELECT voter_id, proxied_vests
  FROM hafbe_views.recursively_proxied_vests_view
) rpv ON rpv.voter_id = cwv.voter_id

LEFT JOIN (
  SELECT account_id, proxy
  FROM hafbe_app.current_account_proxies
) acc_as_proxied ON acc_as_proxied.account_id = cwv.voter_id

LEFT JOIN (
  SELECT vests, account_id
  FROM hafbe_app.account_vests
) account ON account.account_id = cwv.voter_id AND COALESCE(acc_as_proxied.proxy, FALSE) IS FALSE

WHERE cwv.approve IS TRUE;

------

DROP VIEW IF EXISTS hafbe_views.voters_stats_change_view;
CREATE VIEW hafbe_views.voters_stats_change_view AS
SELECT
  witness_id, voter_id, approve, timestamp,
  (
    SUM(CASE WHEN acc_as_proxy.proxy IS TRUE THEN proxied.vests ELSE -1 * proxied.vests END)
      +
    CASE WHEN acc_as_proxied.proxy IS FALSE THEN account.vests ELSE -1 * account.vests END
  ) AS votes
FROM hafbe_app.witness_votes_history

LEFT JOIN (
  SELECT account_id, proxy_id, proxy
  FROM hafbe_app.account_proxies_history
) acc_as_proxy ON acc_as_proxy.proxy_id = voter_id

LEFT JOIN (
  SELECT vests, account_id
  FROM hafbe_app.account_vests
) proxied ON proxied.account_id = acc_as_proxy.account_id

LEFT JOIN (
  SELECT account_id, proxy
  FROM hafbe_app.account_proxies_history
) acc_as_proxied ON acc_as_proxied.account_id = voter_id

LEFT JOIN (
  SELECT vests, account_id
  FROM hafbe_app.account_vests
) account ON account.account_id = acc_as_proxied.account_id

GROUP BY witness_id, voter_id, approve, timestamp, acc_as_proxied.proxy, account.vests;