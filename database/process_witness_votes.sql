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

RESET ROLE;
