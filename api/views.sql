CREATE SCHEMA IF NOT EXISTS hafbe_views;

DROP VIEW IF EXISTS hafbe_views.voters_stats_view;
CREATE VIEW hafbe_views.voters_stats_view AS
SELECT
  witness_id, voter_id, timestamp,
  COALESCE(account.vests, 0)::NUMERIC AS account_vests,
  SUM(COALESCE(proxied.vests, 0)) AS proxied_vests
FROM hafbe_app.current_witness_votes

LEFT JOIN (
  SELECT account_id, proxy_id
  FROM hafbe_app.current_account_proxies
  WHERE proxy = TRUE 
) acc_as_proxy ON acc_as_proxy.proxy_id = voter_id

LEFT JOIN (
  SELECT vests, account_id
  FROM hafbe_app.account_vests
) proxied ON proxied.account_id = acc_as_proxy.account_id

LEFT JOIN (
  SELECT account_id, proxy
  FROM hafbe_app.current_account_proxies
) acc_as_proxied ON acc_as_proxied.account_id = voter_id

LEFT JOIN (
  SELECT vests, account_id
  FROM hafbe_app.account_vests
) account ON account.account_id = voter_id AND COALESCE(acc_as_proxied.proxy, FALSE) IS FALSE

WHERE approve IS TRUE
GROUP BY witness_id, voter_id, account.vests;

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

-----

DROP VIEW IF EXISTS hafbe_views.witness_prop_op_view;
CREATE VIEW hafbe_views.witness_prop_op_view AS
SELECT
  account_id AS witness_id,
  (hov.body::JSON)->'value' AS value,
  hov.timestamp AS timestamp,
  block_num, op_type_id, operation_id
FROM hive.account_operations_view haov

JOIN (
  SELECT body, id, timestamp
  FROM hive.operations_view
) hov ON hov.id = haov.operation_id

ORDER BY operation_id DESC;