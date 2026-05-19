SET ROLE hafbe_owner;

/*
 * process_proposal_vote_stats_cache: Refresh stake-weighted proposal vote totals.
 *
 * Runs every LIVE block (NOT during MASSIVE). Mirrors process_witness_votes_cache:
 * full DELETE + INSERT rather than incremental update. Acceptable because
 * the number of proposals is small (low thousands over Hive's lifetime).
 *
 * Stake-weighting matches hived's `list_proposals(by_total_votes)`:
 *   - sum the vesting power of each direct voter
 *   - skip any voter who has set a governance proxy (their stake is
 *     represented by the proxy's own vote, not added through them).
 *
 * MUST be called AFTER process_witness_votes_cache so account_vest_stats_cache
 * is fresh for the same block.
 *
 * NOTE: Vote-history and current_proposal_votes maintenance lives in
 * process_proposals (unified row-by-row processor for all proposal ops).
 * Only the cache refresh remains in this file.
 */
CREATE OR REPLACE FUNCTION hafbe_app.process_proposal_vote_stats_cache()
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
AS $$
BEGIN
  DELETE FROM hafbe_app.proposal_vote_stats_cache;

  INSERT INTO hafbe_app.proposal_vote_stats_cache (proposal_id, total_votes, voters_num)
  SELECT
    cpv.proposal_id,
    COALESCE(SUM(avs.vests), 0)::BIGINT AS total_votes,
    COUNT(*)::INT                       AS voters_num
  FROM hafbe_app.current_proposal_votes cpv
  LEFT JOIN hafbe_app.account_vest_stats_cache avs ON avs.account_id = cpv.voter_id
  WHERE NOT EXISTS (
    SELECT 1
    FROM hafbe_app.current_account_proxies cap
    WHERE cap.account_id = cpv.voter_id
  )
  GROUP BY cpv.proposal_id;
END
$$;

RESET ROLE;
