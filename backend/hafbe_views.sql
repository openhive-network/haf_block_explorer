DROP SCHEMA IF EXISTS hafbe_views CASCADE;
CREATE SCHEMA IF NOT EXISTS hafbe_views AUTHORIZATION hafbe_owner;

CREATE OR REPLACE VIEW hafbe_views.witness_prop_op_view AS
SELECT
  bia.name AS witness,
  (body)->'value' AS value,
  body_binary,
  block_num, op_type_id, timestamp, id AS operation_id
FROM hive.hafbe_app_operations_view hov

JOIN LATERAL (
  SELECT get_impacted_accounts AS name
  FROM hive.get_impacted_accounts(hov.body_binary)
) bia ON TRUE;

------

CREATE OR REPLACE VIEW hafbe_views.recursive_account_proxies_view AS
WITH proxies1 AS (
  SELECT
    prox1.proxy_id AS top_proxy_id,
    prox1.account_id
  FROM hafbe_app.current_account_proxies prox1
),

proxies2 AS (
  SELECT prox1.top_proxy_id, prox2.account_id
  FROM proxies1 prox1
  JOIN hafbe_app.current_account_proxies prox2 ON prox2.proxy_id = prox1.account_id
),

proxies3 AS (
  SELECT prox2.top_proxy_id, prox3.account_id
  FROM proxies2 prox2
  JOIN hafbe_app.current_account_proxies prox3 ON prox3.proxy_id = prox2.account_id
),

proxies4 AS (
  SELECT prox3.top_proxy_id, prox4.account_id
  FROM proxies3 prox3
  JOIN hafbe_app.current_account_proxies prox4 ON prox4.proxy_id = prox3.account_id
),

proxies5 AS (
  SELECT prox4.top_proxy_id, prox5.account_id
  FROM proxies4 prox4
  JOIN hafbe_app.current_account_proxies prox5 ON prox5.proxy_id = prox4.account_id
)

SELECT top_proxy_id AS proxy_id, account_id
FROM (
  SELECT top_proxy_id, account_id FROM proxies1
  UNION
  SELECT top_proxy_id, account_id FROM proxies2
  UNION
  SELECT top_proxy_id, account_id FROM proxies3
  UNION
  SELECT top_proxy_id, account_id FROM proxies4
  UNION
  SELECT top_proxy_id, account_id FROM proxies5
) rap;

------

CREATE OR REPLACE VIEW hafbe_views.witness_voters_vests_view AS
SELECT
  cwv_cap.witness_id, cwv_cap.voter_id,
  CASE WHEN cwv_cap.proxy_id IS NULL THEN COALESCE(av.vests, 0) ELSE 0 END AS account_vests,
  cwv_cap.timestamp
FROM (
  SELECT cwv.witness_id, cwv.voter_id, cwv.timestamp, cap.proxy_id
  FROM hafbe_app.current_witness_votes cwv
  LEFT JOIN hafbe_app.current_account_proxies cap ON cap.account_id = cwv.voter_id
) cwv_cap
LEFT JOIN hafbe_app.account_vests av ON av.account_id = cwv_cap.voter_id;

------

CREATE OR REPLACE VIEW hafbe_views.voters_proxied_vests_view AS
SELECT
  rapv.proxy_id,
  SUM(av.vests) AS proxied_vests
FROM hafbe_views.recursive_account_proxies_view rapv
JOIN hafbe_app.account_vests av ON av.account_id = rapv.account_id
GROUP BY rapv.proxy_id;

------

CREATE OR REPLACE VIEW hafbe_views.voters_stats_view AS
SELECT
  wvvv.witness_id, wvvv.voter_id,
  wvvv.account_vests + COALESCE(vpvv.proxied_vests, 0) AS vests,
  wvvv.account_vests,
  COALESCE(vpvv.proxied_vests, 0) AS proxied_vests,
  wvvv.timestamp
FROM hafbe_views.witness_voters_vests_view wvvv
LEFT JOIN hafbe_views.voters_proxied_vests_view vpvv ON vpvv.proxy_id = wvvv.voter_id;

------

CREATE OR REPLACE VIEW hafbe_views.voters_approve_vests_change_view AS
SELECT
  wvh.witness_id, wvh.voter_id, wvh.approve, wvh.timestamp,
  CASE WHEN wvh.approve THEN av.vests ELSE -1 * av.vests END AS account_vests,
  CASE WHEN wvh.approve THEN COALESCE(rpav.proxied_vests, 0) ELSE -1 * COALESCE(rpav.proxied_vests, 0) END AS proxied_vests
FROM hafbe_app.witness_votes_history wvh

JOIN (
  SELECT vests, account_id
  FROM hafbe_app.account_vests
) av ON av.account_id = wvh.voter_id

LEFT JOIN LATERAL (
  SELECT proxy_id, proxied_vests
  FROM hafbe_views.voters_proxied_vests_view
  WHERE proxy_id = wvh.voter_id
) rpav ON TRUE;

------

CREATE OR REPLACE VIEW hafbe_views.voters_proxy_vests_change_view AS
SELECT
  aph.account_id AS voter_id,
  SUM(CASE WHEN aph.proxy THEN -1 * av.vests ELSE av.vests END) AS account_vests,
  SUM(CASE WHEN aph.proxy THEN -1 * COALESCE(rpav.proxied_vests, 0) ELSE COALESCE(rpav.proxied_vests, 0) END) AS proxied_vests
FROM hafbe_app.account_proxies_history aph

JOIN (
  SELECT vests, account_id
  FROM hafbe_app.account_vests
) av ON av.account_id = aph.account_id

LEFT JOIN LATERAL (
  SELECT proxy_id, proxied_vests
  FROM hafbe_views.voters_proxied_vests_view
  WHERE proxy_id = aph.account_id
) rpav ON TRUE
GROUP BY aph.account_id;

------

CREATE OR REPLACE VIEW hafbe_views.voters_stats_change_view AS
SELECT
  vavcv.witness_id, vavcv.voter_id,
  vavcv.account_vests + vavcv.proxied_vests + COALESCE(vpvcv.account_vests, 0) + COALESCE(vpvcv.proxied_vests, 0) AS vests,
  vavcv.account_vests + vavcv.proxied_vests AS account_vests,
  COALESCE(vpvcv.account_vests, 0) + COALESCE(vpvcv.proxied_vests, 0) AS proxied_vests,
  vavcv.approve, vavcv.timestamp
FROM hafbe_views.voters_approve_vests_change_view vavcv

LEFT JOIN LATERAL (
  SELECT voter_id, account_vests, proxied_vests
  FROM hafbe_views.voters_proxy_vests_change_view
  WHERE voter_id = vavcv.voter_id
) vpvcv ON TRUE;
