DROP SCHEMA IF EXISTS hafbe_views CASCADE;

CREATE SCHEMA hafbe_views AUTHORIZATION hafbe_owner;

DROP VIEW IF EXISTS hafbe_views.voters_account_vests_view CASCADE;
CREATE VIEW hafbe_views.voters_account_vests_view AS
SELECT
  av.account_id AS voter_id,
  CASE WHEN cap.account_id IS NULL THEN av.vests ELSE 0 END AS account_vests
FROM hafbe_app.account_vests av

LEFT JOIN LATERAL (
  SELECT account_id
  FROM hafbe_app.current_account_proxies
  WHERE account_id = av.account_id
) cap ON TRUE;

------

DROP VIEW IF EXISTS hafbe_views.voters_proxied_vests_view CASCADE;
CREATE VIEW hafbe_views.voters_proxied_vests_view AS
SELECT
  rap.proxy_id,
  SUM(av.vests) AS proxied_vests
FROM hafbe_app.recursive_account_proxies rap

JOIN (
  SELECT account_id, vests
  FROM hafbe_app.account_vests
) av ON av.account_id = rap.account_id
GROUP BY rap.proxy_id;

------

DROP VIEW IF EXISTS hafbe_views.voters_stats_view CASCADE;
CREATE VIEW hafbe_views.voters_stats_view AS
SELECT
  cwv.witness_id, cwv.voter_id,
  COALESCE(vavv.account_vests, 0) + COALESCE(vpvv.proxied_vests, 0) AS vests,
  COALESCE(vavv.account_vests, 0) AS account_vests,
  COALESCE(vpvv.proxied_vests, 0) AS proxied_vests,
  cwv.timestamp
FROM hafbe_app.current_witness_votes cwv

LEFT JOIN LATERAL (
  SELECT voter_id, account_vests
  FROM hafbe_views.voters_account_vests_view
  WHERE voter_id = cwv.voter_id
) vavv ON TRUE

LEFT JOIN LATERAL (
  SELECT proxy_id, proxied_vests
  FROM hafbe_views.voters_proxied_vests_view
  WHERE proxy_id = cwv.voter_id
) vpvv ON TRUE;

------

DROP VIEW IF EXISTS hafbe_views.voters_history_account_vests_view CASCADE;
CREATE VIEW hafbe_views.voters_history_account_vests_view AS
SELECT wvh.witness_id, wvh.voter_id, wvh.approve, wvh.timestamp, av.vests  
FROM hafbe_app.witness_votes_history wvh

JOIN (
  SELECT vests, account_id
  FROM hafbe_app.account_vests
) av ON av.account_id = wvh.voter_id;

------

DROP VIEW IF EXISTS hafbe_views.voters_approve_vests_change_view CASCADE;
CREATE VIEW hafbe_views.voters_approve_vests_change_view AS
SELECT
  wvh.witness_id, wvh.voter_id, wvh.approve, wvh.timestamp,
  CASE WHEN wvh.approve THEN av.vests ELSE -1 * av.vests END AS approve_votes_change,
  CASE WHEN wvh.approve THEN COALESCE(rpav.proxied_vests, 0) ELSE -1 * COALESCE(rpav.proxied_vests, 0) END AS proxy_votes_change
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

DROP VIEW IF EXISTS hafbe_views.voters_proxy_vests_change_view CASCADE;
CREATE VIEW hafbe_views.voters_proxy_vests_change_view AS
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

DROP VIEW IF EXISTS hafbe_views.voters_stats_change_view CASCADE;
CREATE VIEW hafbe_views.voters_stats_change_view AS
SELECT
  vavcv.witness_id,
  SUM(
    vavcv.approve_votes_change + vavcv.proxy_votes_change
      +
    COALESCE(vpvcv.account_vests, 0) + COALESCE(vpvcv.proxied_vests, 0)
  ) AS votes_daily_change,
  SUM(CASE WHEN vavcv.approve THEN 1 ELSE -1 END) AS voters_num_daily_change,
  MAX(vavcv.timestamp) AS timestamp
FROM hafbe_views.voters_approve_vests_change_view vavcv

LEFT JOIN LATERAL (
  SELECT voter_id, account_vests, proxied_vests
  FROM hafbe_views.voters_proxy_vests_change_view
  WHERE voter_id = vavcv.voter_id
) vpvcv ON TRUE
GROUP BY vavcv.witness_id;