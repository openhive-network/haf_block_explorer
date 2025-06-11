SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_app.process_witness_votes(_from INT, _to INT)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
AS
$$
DECLARE
  _result INT;
BEGIN
-- function used to calculate witness votes and proxies
-- updates tables hafbe_app.current_account_proxies, hafbe_app.current_witness_votes, hafbe_app.witness_votes_history, hafbe_app.account_proxies_history
  WITH proxy_ops_without_timestamp AS MATERIALIZED (
    SELECT 
      ov.body AS body,
      ov.id,
      ov.block_num,
      ov.op_type_id as op_type
    FROM hafbe_app.operations_view ov
    WHERE 
      ov.op_type_id IN (12,13,91,92,75) AND
      ov.block_num BETWEEN _from AND _to
  ),
  proxy_ops AS (
    SELECT 
      proxy_ops_w_t.body,
      proxy_ops_w_t.id,
      proxy_ops_w_t.block_num,
      proxy_ops_w_t.op_type,
      hb.created_at timestamp
    FROM proxy_ops_without_timestamp proxy_ops_w_t
    JOIN hive.blocks_view hb ON hb.num = proxy_ops_w_t.block_num
  ),
  balance_change AS (
    SELECT
      bc.id,
      hafbe_backend.process_votes_and_proxies(bc.body, bc.op_type, bc.id, bc.block_num) AS result
    FROM proxy_ops bc
    ORDER BY bc.id
  )
  SELECT COUNT(*) FROM balance_change INTO _result;

END
$$;


CREATE OR REPLACE FUNCTION hafbe_app.process_witness_votes_cache()
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
AS
$$
DECLARE
  _first_block_num INT := (SELECT num FROM hive.blocks_view WHERE created_at <= 'today'::DATE ORDER BY num DESC LIMIT 1);
BEGIN
--------------------------------------------------------
  DELETE FROM hafbe_app.account_vest_stats_cache;

  INSERT INTO hafbe_app.account_vest_stats_cache (account_id, vests, account_vests, proxied_vests)
    SELECT 
      account_id,
      vests,
      account_vests,
      proxied_vests
    FROM hafbe_backend.account_vest_stats_view;
--------------------------------------------------------
  DELETE FROM hafbe_app.witness_votes_cache;

  INSERT INTO hafbe_app.witness_votes_cache (witness_id, votes, voters_num)
    SELECT 
      cwv.witness_id, 
      SUM(avs.vests)::BIGINT,
      COUNT(*)
    FROM hafbe_app.current_witness_votes cwv
    JOIN hafbe_app.account_vest_stats_cache avs ON avs.account_id = cwv.voter_id
    GROUP BY cwv.witness_id;
--------------------------------------------------------
  DELETE FROM hafbe_app.witness_votes_change_cache;

  INSERT INTO hafbe_app.witness_votes_change_cache (witness_id, votes_daily_change, voters_num_daily_change)
    SELECT
      wvhc.witness_id,
      SUM(CASE WHEN wvhc.approve THEN avs.vests ELSE -1 * (avs.vests) END)::BIGINT,
      SUM(CASE WHEN wvhc.approve THEN 1 ELSE -1 END)::INT
    FROM hafbe_app.witness_votes_history wvhc
    JOIN hafbe_app.account_vest_stats_cache avs ON avs.account_id = wvhc.voter_id
    WHERE wvhc.source_op_block >= _first_block_num
    GROUP BY wvhc.witness_id;
--------------------------------------------------------

END
$$;

RESET ROLE;
