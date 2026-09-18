SET ROLE hafbe_owner;

/*
 * process_proposal_vote_stats_cache: Refresh stake-weighted proposal vote totals.
 *
 * Runs every LIVE block (NOT during MASSIVE). Mirrors process_witness_votes_cache:
 * the totals are fully recomputed (cheap: low thousands of proposals over Hive's
 * lifetime) but applied with MERGE, so only rows whose totals changed are
 * written. See process_witness_votes_cache for why rewriting every row every
 * block was harmful (WAL volume and unvacuumable bloat under long snapshots).
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
  MERGE INTO hafbe_app.proposal_vote_stats_cache t
  USING (
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
    GROUP BY cpv.proposal_id
  ) s ON t.proposal_id = s.proposal_id
  WHEN MATCHED AND (t.total_votes, t.voters_num) IS DISTINCT FROM (s.total_votes, s.voters_num) THEN
    UPDATE SET total_votes = s.total_votes, voters_num = s.voters_num
  WHEN NOT MATCHED THEN
    INSERT (proposal_id, total_votes, voters_num) VALUES (s.proposal_id, s.total_votes, s.voters_num)
  WHEN NOT MATCHED BY SOURCE THEN DELETE;
END
$$;

RESET ROLE;
