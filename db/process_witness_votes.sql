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
  -- Operation type IDs for witness votes and proxies
  _op_account_witness_vote         INT := hafbe_backend.op_account_witness_vote();
  _op_account_witness_proxy        INT := hafbe_backend.op_account_witness_proxy();
  _op_proxy_cleared                INT := hafbe_backend.op_proxy_cleared();
  _op_declined_voting_rights       INT := hafbe_backend.op_declined_voting_rights();
  _op_expired_account_notification INT := hafbe_backend.op_expired_account_notification();
  _result                          INT;
BEGIN
-- function used to calculate witness votes and proxies
-- updates tables hafbe_app.current_account_proxies, hafbe_app.current_witness_votes, hafbe_app.witness_votes_history, hafbe_app.account_proxies_history
  WITH proxy_ops AS MATERIALIZED (
    SELECT
      ov.body AS body,
      ov.id,
      ov.block_num,
      ov.op_type_id AS op_type
    FROM hafbe_app.operations_view ov
    WHERE
      ov.op_type_id IN (_op_account_witness_vote, _op_account_witness_proxy, _op_proxy_cleared, _op_declined_voting_rights, _op_expired_account_notification) AND
      ov.block_num BETWEEN _from AND _to
  ),
  balance_change AS (
    SELECT
      bc.id,
      (
        CASE
          WHEN bc.op_type = _op_account_witness_vote THEN
            hafbe_backend.process_vote_op(bc.body, bc.id)
          WHEN bc.op_type = _op_account_witness_proxy THEN
            hafbe_backend.process_proxy_ops(bc.body, bc.id, TRUE)
          WHEN bc.op_type = _op_proxy_cleared THEN
            hafbe_backend.process_proxy_ops(bc.body, bc.id, FALSE)
          WHEN bc.op_type = _op_declined_voting_rights OR bc.op_type = _op_expired_account_notification THEN
            hafbe_backend.process_expired_accounts(bc.body, bc.id)
        END
      ) AS result
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
    FROM hafbe_backend.current_witness_votes_view cwv
    JOIN hafbe_app.account_vest_stats_cache avs ON avs.account_id = cwv.voter_id
    GROUP BY cwv.witness_id;
--------------------------------------------------------
  DELETE FROM hafbe_app.witness_rank_cache;

  INSERT INTO hafbe_app.witness_rank_cache (witness_id, rank)
    SELECT
      cw.witness_id,
      ROW_NUMBER() OVER (ORDER BY COALESCE(wv.votes,0) DESC, COALESCE(wv.voters_num,0) DESC, cw.witness_id DESC)
    FROM hafbe_app.current_witnesses cw
    LEFT JOIN hafbe_app.witness_votes_cache wv ON wv.witness_id = cw.witness_id;
--------------------------------------------------------
  DELETE FROM hafbe_app.witness_votes_change_cache;

  INSERT INTO hafbe_app.witness_votes_change_cache (witness_id, votes_daily_change, voters_num_daily_change)
    SELECT
      wvhc.witness_id,
      SUM(CASE WHEN wvhc.approve THEN avs.vests ELSE -1 * (avs.vests) END)::BIGINT,
      SUM(CASE WHEN wvhc.approve THEN 1 ELSE -1 END)::INT
    FROM hafbe_backend.witness_votes_history_view wvhc
    JOIN hafbe_app.account_vest_stats_cache avs ON avs.account_id = wvhc.voter_id
    WHERE wvhc.source_op_block >= _first_block_num
    GROUP BY wvhc.witness_id;
--------------------------------------------------------

END
$$;

RESET ROLE;
