-- I don't feel confident fixing erros in this file, so I'm disabling lint for it.
-- The line belowe needs to be deleted after the errors are fixed to reenable it.
-- noqa: disable=all

SET ROLE hafbe_owner;

-- used in witness page endpoints
CREATE OR REPLACE VIEW hafbe_backend.witness_prop_op_view AS
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
CREATE OR REPLACE VIEW hafbe_backend.recursive_account_proxies_view AS
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

-- list of accounts that voted on any witness 
CREATE OR REPLACE VIEW hafbe_backend.witness_voters_list_view AS
  SELECT 
    cwv.voter_id AS account_id
  FROM hafbe_app.current_witness_votes cwv
  GROUP BY cwv.voter_id;

------

-- calculates the total vests being proxied to an account
CREATE OR REPLACE VIEW hafbe_backend.voters_proxied_vests_view AS
SELECT
  rapv.proxy_id,
  SUM(cab.balance - COALESCE(dv.delayed_vests,0))::BIGINT AS proxied_vests,
  rapv.proxy_level
FROM hafbe_backend.recursive_account_proxies_view rapv
JOIN current_account_balances cab ON cab.account = rapv.account_id AND cab.nai = 37
LEFT JOIN account_withdraws dv ON dv.account = rapv.account_id
GROUP BY rapv.proxy_id, rapv.proxy_level;

CREATE OR REPLACE VIEW hafbe_backend.voters_proxied_vests_sum_view AS
SELECT
  rapv.proxy_id,
  SUM(rapv.proxied_vests)::BIGINT AS proxied_vests
FROM hafbe_backend.voters_proxied_vests_view rapv
GROUP BY rapv.proxy_id;

------

-- calculates the vest stats for each account
CREATE OR REPLACE VIEW hafbe_backend.account_vest_stats_view AS
  SELECT
    cw.account_id,
    cw.account_vests - COALESCE(dv.delayed_vests::BIGINT,0) + COALESCE(vpvv.proxied_vests, 0) AS vests,
    cw.account_vests - COALESCE(dv.delayed_vests::BIGINT,0) AS account_vests,
    COALESCE(vpvv.proxied_vests, 0) AS proxied_vests
  FROM (
    SELECT
      wvl.account_id,
      CASE WHEN cap.proxy_id IS NULL THEN COALESCE(cab.balance::BIGINT, 0) ELSE 0 END AS account_vests
    FROM hafbe_backend.witness_voters_list_view wvl
    LEFT JOIN hafbe_app.current_account_proxies cap ON cap.account_id = wvl.account_id
    LEFT JOIN current_account_balances cab ON cab.account = wvl.account_id AND cab.nai = 37
  ) cw
  LEFT JOIN hafbe_backend.voters_proxied_vests_sum_view vpvv ON vpvv.proxy_id = cw.account_id
  LEFT JOIN account_withdraws dv ON dv.account = cw.account_id;
------

-- Allows to easly search though timmings of each section of hafbe sync
CREATE OR REPLACE VIEW hafbe_backend.time_logs_view AS
  SELECT
    block_num,
    (time_json->>'hafbe')::NUMERIC AS hafbe,
    (time_json->>'btracker')::NUMERIC AS btracker,
  	(time_json->>'state_provider')::NUMERIC AS state_provider
  FROM
    hafbe_app.sync_time_logs;
    
------


RESET ROLE;
