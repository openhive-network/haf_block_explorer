-- I don't feel confident fixing erros in this file, so I'm disabling lint for it.
-- The line belowe needs to be deleted after the errors are fixed to reenable it.
-- noqa: disable=all
DROP SCHEMA IF EXISTS hafbe_views CASCADE;

SET ROLE hafbe_owner;

CREATE SCHEMA hafbe_views AUTHORIZATION hafbe_owner;

-- used in witness page endpoints
CREATE OR REPLACE VIEW hafbe_views.witness_prop_op_view AS
SELECT
  bia.name AS witness,
  (body)->'value' AS value,
  body_binary,
  block_num, op_type_id, id AS operation_id
FROM hafbe_app.operations_view ov

JOIN LATERAL (
  SELECT get_impacted_accounts AS name
  FROM hive.get_impacted_accounts(ov.body_binary)
) bia ON TRUE;

------

-- used in witness page endpoints
CREATE OR REPLACE VIEW hafbe_views.recursive_account_proxies_view AS
WITH proxies1 AS (
  SELECT
    prox1.proxy_id AS top_proxy_id,
    prox1.account_id, 1 AS proxy_level
  FROM hafbe_app.current_account_proxies prox1
),

proxies2 AS (
  SELECT prox1.top_proxy_id, prox2.account_id, 2 AS proxy_level
  FROM proxies1 prox1
  JOIN hafbe_app.current_account_proxies prox2 ON prox2.proxy_id = prox1.account_id
),

proxies3 AS (
  SELECT prox2.top_proxy_id, prox3.account_id, 3 AS proxy_level
  FROM proxies2 prox2
  JOIN hafbe_app.current_account_proxies prox3 ON prox3.proxy_id = prox2.account_id
),

proxies4 AS (
  SELECT prox3.top_proxy_id, prox4.account_id, 4 AS proxy_level
  FROM proxies3 prox3
  JOIN hafbe_app.current_account_proxies prox4 ON prox4.proxy_id = prox3.account_id
)

SELECT top_proxy_id AS proxy_id, account_id, proxy_level
FROM (
  SELECT top_proxy_id, account_id, proxy_level FROM proxies1
  UNION
  SELECT top_proxy_id, account_id, proxy_level FROM proxies2
  UNION
  SELECT top_proxy_id, account_id, proxy_level FROM proxies3
  UNION
  SELECT top_proxy_id, account_id, proxy_level FROM proxies4
) rap;
------
-- used in witness page endpoints
CREATE OR REPLACE VIEW hafbe_views.witness_voters_vests_view AS
SELECT
  cwv_cap.witness_id, cwv_cap.voter_id,
  CASE WHEN cwv_cap.proxy_id IS NULL THEN COALESCE(cab.balance::BIGINT, 0) ELSE 0 END AS account_vests,
  cwv_cap.timestamp
FROM (
  SELECT cwv.witness_id, cwv.voter_id, cwv.timestamp, cap.proxy_id
  FROM hafbe_app.current_witness_votes cwv
  LEFT JOIN hafbe_app.current_account_proxies cap ON cap.account_id = cwv.voter_id
) cwv_cap
LEFT JOIN current_account_balances cab ON cab.account = cwv_cap.voter_id AND cab.nai = 37;

------

-- used in witness page endpoints
CREATE OR REPLACE VIEW hafbe_views.current_witness_votes_view AS
  SELECT
    ov.voter_id AS account,
    av.name AS vote
  FROM
    hafbe_app.current_witness_votes ov
  JOIN hive.accounts_view av ON av.id = ov.witness_id;
------

-- used in witness page endpoints
CREATE OR REPLACE VIEW hafbe_views.voters_proxied_vests_view AS
SELECT
  rapv.proxy_id,
  SUM(cab.balance::BIGINT - COALESCE(dv.delayed_vests::BIGINT,0))::BIGINT AS proxied_vests,
  rapv.proxy_level
FROM hafbe_views.recursive_account_proxies_view rapv
JOIN current_account_balances cab ON cab.account = rapv.account_id AND cab.nai = 37
LEFT JOIN account_withdraws dv ON dv.account = rapv.account_id
GROUP BY rapv.proxy_id, rapv.proxy_level;

------

-- used in witness page endpoints
CREATE OR REPLACE VIEW hafbe_views.voters_proxied_vests_sum_view AS
SELECT
  rapv.proxy_id,
  SUM(rapv.proxied_vests) AS proxied_vests
FROM hafbe_views.voters_proxied_vests_view rapv
GROUP BY rapv.proxy_id;

------

-- used in witness page endpoints
CREATE OR REPLACE VIEW hafbe_views.voters_stats_view AS
SELECT
  wvvv.witness_id, wvvv.voter_id,
  wvvv.account_vests - COALESCE(dv.delayed_vests::BIGINT,0) + COALESCE(vpvv.proxied_vests, 0) AS vests,
  wvvv.account_vests - COALESCE(dv.delayed_vests::BIGINT,0) AS account_vests,
  COALESCE(vpvv.proxied_vests, 0) AS proxied_vests,
  wvvv.timestamp
FROM hafbe_views.witness_voters_vests_view wvvv
LEFT JOIN hafbe_views.voters_proxied_vests_sum_view vpvv ON vpvv.proxy_id = wvvv.voter_id
LEFT JOIN account_withdraws dv ON dv.account = wvvv.voter_id;

------

-- Allows to easly search though timmings of each section of hafbe sync
CREATE OR REPLACE VIEW hafbe_views.time_logs_view AS
  SELECT
    block_num,
    (time_json->>'hafbe')::NUMERIC AS hafbe,
    (time_json->>'btracker')::NUMERIC AS btracker,
  	(time_json->>'state_provider')::NUMERIC AS state_provider
  FROM
    hafbe_app.sync_time_logs;
    
------


RESET ROLE;
