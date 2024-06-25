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
CREATE OR REPLACE VIEW hafbe_views.recursive_account_proxies_stats_view AS
SELECT
  rapv.proxy_id,
  (SELECT av.name FROM hive.accounts_view av WHERE av.id = rapv.account_id) as name,
  (cab.balance - COALESCE(dv.delayed_vests,0)) AS proxied_vests,
  rapv.proxy_level
FROM hafbe_views.recursive_account_proxies_view rapv
JOIN btracker_app.current_account_balances cab ON cab.account = rapv.account_id AND cab.nai = 37
LEFT JOIN btracker_app.account_withdraws dv ON dv.account = rapv.account_id;

------

-- used in witness page endpoints
CREATE OR REPLACE VIEW hafbe_views.witness_voters_vests_view AS
SELECT
  cwv_cap.witness_id, cwv_cap.voter_id,
  CASE WHEN cwv_cap.proxy_id IS NULL THEN COALESCE(cab.balance, 0) ELSE 0 END AS account_vests,
  cwv_cap.timestamp
FROM (
  SELECT cwv.witness_id, cwv.voter_id, cwv.timestamp, cap.proxy_id
  FROM hafbe_app.current_witness_votes cwv
  LEFT JOIN hafbe_app.current_account_proxies cap ON cap.account_id = cwv.voter_id
) cwv_cap
LEFT JOIN btracker_app.current_account_balances cab ON cab.account = cwv_cap.voter_id AND cab.nai = 37;

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
  SUM(cab.balance - COALESCE(dv.delayed_vests,0))::BIGINT AS proxied_vests,
  rapv.proxy_level
FROM hafbe_views.recursive_account_proxies_view rapv
JOIN btracker_app.current_account_balances cab ON cab.account = rapv.account_id AND cab.nai = 37
LEFT JOIN btracker_app.account_withdraws dv ON dv.account = rapv.account_id
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
  wvvv.account_vests - COALESCE(dv.delayed_vests,0) + COALESCE(vpvv.proxied_vests, 0) AS vests,
  wvvv.account_vests - COALESCE(dv.delayed_vests,0) AS account_vests,
  COALESCE(vpvv.proxied_vests, 0) AS proxied_vests,
  wvvv.timestamp
FROM hafbe_views.witness_voters_vests_view wvvv
LEFT JOIN hafbe_views.voters_proxied_vests_sum_view vpvv ON vpvv.proxy_id = wvvv.voter_id
LEFT JOIN btracker_app.account_withdraws dv ON dv.account = wvvv.voter_id;

------

-- used in witness page endpoints
CREATE OR REPLACE VIEW hafbe_views.voters_approve_vests_change_view AS
SELECT
  wvh.witness_id, wvh.voter_id, wvh.approve, wvh.timestamp,
  CASE WHEN wvh.approve THEN COALESCE(cab.balance,0) ELSE -1 * COALESCE(cab.balance,0) END AS account_vests,
  CASE WHEN wvh.approve THEN COALESCE(rpav.proxied_vests, 0) ELSE -1 * COALESCE(rpav.proxied_vests, 0) END AS proxied_vests
FROM hafbe_app.witness_votes_history wvh

JOIN (
  SELECT balance, account, nai
  FROM btracker_app.current_account_balances
) cab ON cab.account = wvh.voter_id AND cab.nai = 37

LEFT JOIN LATERAL (
  SELECT proxy_id, proxied_vests
  FROM hafbe_views.voters_proxied_vests_sum_view
  WHERE proxy_id = wvh.voter_id
) rpav ON TRUE;

------

-- used in witness page endpoints
CREATE OR REPLACE VIEW hafbe_views.voters_proxy_vests_change_view AS
SELECT
  aph.account_id AS voter_id,
  SUM(CASE WHEN aph.proxy THEN -1 * cab.balance ELSE cab.balance END) AS account_vests,
  SUM(CASE WHEN aph.proxy THEN -1 * COALESCE(rpav.proxied_vests, 0) ELSE COALESCE(rpav.proxied_vests, 0) END) AS proxied_vests
FROM hafbe_app.account_proxies_history aph

JOIN (
  SELECT balance, account, nai
  FROM btracker_app.current_account_balances 
) cab ON cab.account = aph.account_id AND cab.nai = 37

LEFT JOIN LATERAL (
  SELECT proxy_id, proxied_vests
  FROM hafbe_views.voters_proxied_vests_sum_view
  WHERE proxy_id = aph.account_id
) rpav ON TRUE
GROUP BY aph.account_id;

------

-- used in hafbe_app.process_block_range_data_c
CREATE OR REPLACE VIEW hafbe_views.votes_view
AS
  WITH select_operations AS
  (
    SELECT
      (ov.body)->'value'->>'voter' AS voter,
      ov.block_num,
      ov.id
    FROM
      hafbe_app.operations_view ov
    WHERE 
      ov.op_type_id = 72
  )
  SELECT so.voter, so.block_num, so.id, hb.created_at timestamp
  FROM select_operations so
  JOIN hive.blocks_view hb ON hb.num = so.block_num;

------

-- used in hafbe_app.process_block_range_data_c
CREATE OR REPLACE VIEW hafbe_views.pow_view
AS
  SELECT
    (ov.body)->'value'->>'worker_account' AS worker_account,
    ov.block_num,
    ov.id
  FROM
    hafbe_app.operations_view ov
  WHERE 
    ov.op_type_id = 14;

------

-- used in hafbe_app.process_block_range_data_c
CREATE OR REPLACE VIEW hafbe_views.pow_two_view
AS
  SELECT
    (ov.body)->'value'->'work'->'value'->'input'->>'worker_account' AS worker_account,
    ov.block_num,
    ov.id
  FROM
    hafbe_app.operations_view ov
  WHERE 
    ov.op_type_id = 30;

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

------

-- Allows to easly search though timmings of each section of hafbe sync
CREATE OR REPLACE VIEW hafbe_views.time_logs_view AS
  SELECT
    block_num,
    (time_json->>'btracker_app_a')::NUMERIC AS btracker_app_a,
  	(time_json->>'btracker_app_b')::NUMERIC AS btracker_app_b,
    (time_json->>'reptracker_app_a')::NUMERIC AS reptracker_app_b,
    (time_json->>'hafbe_app_a')::NUMERIC AS hafbe_app_a,
  	(time_json->>'hafbe_app_b')::NUMERIC AS hafbe_app_b,
    (time_json->>'hafbe_app_c')::NUMERIC AS hafbe_app_c,
  	(time_json->>'state_provider')::NUMERIC AS state_provider
  FROM
    hafbe_app.sync_time_logs;
    
------

-- used in witness page endpoints
CREATE OR REPLACE VIEW hafbe_views.votes_history_view AS
WITH select_range AS (
  SELECT
    wvh.witness_id, wvh.voter_id, wvh.approve, wvh.timestamp,
    COALESCE(cab.balance, 0) - COALESCE(dv.delayed_vests, 0) AS balance,
    COALESCE(rpav.proxied_vests, 0) AS proxied_vests
  FROM hafbe_app.witness_votes_history wvh
  LEFT JOIN btracker_app.current_account_balances cab
    ON cab.account = wvh.voter_id AND cab.nai = 37
  LEFT JOIN btracker_app.account_withdraws dv
  	ON dv.account = wvh.voter_id
  LEFT JOIN hafbe_views.voters_proxied_vests_sum_view rpav
  ON rpav.proxy_id = wvh.voter_id
)

SELECT
  wvh.witness_id, 
  (SELECT av.name FROM hive.accounts_view av WHERE av.id = wvh.voter_id) as name,
  wvh.approve, wvh.timestamp, 
  (wvh.balance + COALESCE(wvh.proxied_vests, 0))::BIGINT  AS vests, 
  (wvh.balance)::BIGINT  AS account_vests, 
  (COALESCE(wvh.proxied_vests, 0))::BIGINT AS proxied_vests
FROM select_range wvh
ORDER BY wvh.timestamp desc
;

RESET ROLE;
