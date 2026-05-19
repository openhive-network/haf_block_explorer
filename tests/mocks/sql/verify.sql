-- =============================================================================
-- Mock proposal data verification.
--
-- Asserts the expected post-processing state for the fixture in
-- tests/mocks/fixtures/proposals/data.json.
--
-- Scenario recap (after process_proposals + cache refresh):
--   - proposal 9001 created, voted by steem+dan, then 9001 is REMOVED -> votes cascaded away
--   - proposal 9002 created, voted by steem (later cleared by decline) and initminer (survives)
--   - proposal 9002 daily_pay updated 100000 -> 50000
--   - proposal 9002 received one payment of 50000
--
-- Expected final state:
--   current_proposals:           9001 removed=TRUE / 9002 removed=FALSE daily=50000
--   current_proposal_votes:      ONE row: (initminer, 9002)
--   proposal_payments:           ONE row: (9002, 50000)
--   proposal_votes_history:      9 rows total (5 TRUE inserts + 4 FALSE cascades)
--   proposal_vote_stats_cache:   ONE row for 9002, voters_num=1
--
-- EXIT BEHAVIOR
--   Prints a PASS/FAIL table for visibility, then RAISES EXCEPTION if any
--   row failed so the installer (psql -v ON_ERROR_STOP=on) exits non-zero
--   and CI fails the job.
-- =============================================================================

\echo
\echo '====== HAFBE proposal mock verification ======'
\echo

CREATE TEMP VIEW _hafbe_mock_checks AS
WITH checks(name, expected, actual) AS (
  VALUES
    ('current_proposals row count',
       '2',
       (SELECT COUNT(*)::TEXT FROM hafbe_app.current_proposals
        WHERE proposal_id IN (9001, 9002))),

    ('proposal 9001 marked removed',
       'true',
       (SELECT removed::TEXT FROM hafbe_app.current_proposals WHERE proposal_id = 9001)),

    ('proposal 9002 NOT removed',
       'false',
       (SELECT removed::TEXT FROM hafbe_app.current_proposals WHERE proposal_id = 9002)),

    ('proposal 9002 daily_pay reflects update (50000)',
       '50000',
       (SELECT daily_pay::TEXT FROM hafbe_app.current_proposals WHERE proposal_id = 9002)),

    ('proposal 9001 daily_pay unchanged (240000)',
       '240000',
       (SELECT daily_pay::TEXT FROM hafbe_app.current_proposals WHERE proposal_id = 9001)),

    ('current_proposal_votes count = 1 (only initminer->9002 survives)',
       '1',
       (SELECT COUNT(*)::TEXT FROM hafbe_app.current_proposal_votes
        WHERE proposal_id IN (9001, 9002))),

    ('surviving vote is initminer -> 9002',
       'initminer|9002',
       (SELECT av.name || '|' || cpv.proposal_id::TEXT
        FROM hafbe_app.current_proposal_votes cpv
        JOIN hafbe_app.accounts_view av ON av.id = cpv.voter_id
        WHERE cpv.proposal_id IN (9001, 9002))),

    ('NO active votes for removed proposal 9001 (cascade fix)',
       '0',
       (SELECT COUNT(*)::TEXT FROM hafbe_app.current_proposal_votes WHERE proposal_id = 9001)),

    ('NO active votes from declined account steem (cascade fix)',
       '0',
       (SELECT COUNT(*)::TEXT FROM hafbe_app.current_proposal_votes cpv
        JOIN hafbe_app.accounts_view av ON av.id = cpv.voter_id
        WHERE av.name = 'steem' AND cpv.proposal_id IN (9001, 9002))),

    ('proposal_votes_history count = 9 (5 TRUE inserts + 4 FALSE cascades)',
       '9',
       (SELECT COUNT(*)::TEXT FROM hafbe_app.proposal_votes_history
        WHERE proposal_id IN (9001, 9002))),

    ('proposal_payments has 1 row for 9002, amount 50000',
       '9002|50000',
       (SELECT proposal_id::TEXT || '|' || amount::TEXT
        FROM hafbe_app.proposal_payments WHERE proposal_id = 9002)),

    ('proposal_vote_stats_cache has 1 row (only 9002)',
       '1',
       (SELECT COUNT(*)::TEXT FROM hafbe_app.proposal_vote_stats_cache
        WHERE proposal_id IN (9001, 9002))),

    ('proposal_vote_stats_cache 9002 voters_num = 1',
       '1',
       (SELECT voters_num::TEXT FROM hafbe_app.proposal_vote_stats_cache
        WHERE proposal_id = 9002)),

    -- ----- Endpoint-level assertions -----
    -- Catch composition bugs that table-level checks above cannot: removed
    -- filter, paid_amount join, voters_num/total_votes wiring, nested
    -- proposal composite in /proposals/votes.

    ('get_proposals.total_proposals excludes removed (= 1, not 2)',
       '1',
       (SELECT (hafbe_endpoints.get_proposals(1, 100, 'by_total_votes', 'desc', 'all')).total_proposals::TEXT)),

    ('get_proposals.proposals contains 9002 (not removed)',
       '9002',
       (SELECT p.proposal_id::TEXT FROM unnest(
          (hafbe_endpoints.get_proposals(1, 100, 'by_total_votes', 'desc', 'all')).proposals
        ) p WHERE p.proposal_id = 9002)),

    ('get_proposals.proposals does NOT contain removed 9001',
       'true',
       (SELECT (NOT EXISTS (SELECT 1 FROM unnest(
          (hafbe_endpoints.get_proposals(1, 100, 'by_total_votes', 'desc', 'all')).proposals
        ) p WHERE p.proposal_id = 9001))::TEXT)),

    ('get_proposals row for 9002 reports paid_amount=50000',
       '50000',
       (SELECT p.paid_amount FROM unnest(
          (hafbe_endpoints.get_proposals(1, 100, 'by_total_votes', 'desc', 'all')).proposals
        ) p WHERE p.proposal_id = 9002)),

    ('get_proposals row for 9002 reports voters_num=1',
       '1',
       (SELECT p.voters_num::TEXT FROM unnest(
          (hafbe_endpoints.get_proposals(1, 100, 'by_total_votes', 'desc', 'all')).proposals
        ) p WHERE p.proposal_id = 9002)),

    ('get_proposal_votes.total_votes = 1 (only initminer->9002 active)',
       '1',
       (SELECT (hafbe_endpoints.get_proposal_votes(1, 100, 'by_proposal_voter', 'asc', 'all')).total_votes::TEXT)),

    ('get_proposal_votes returns voter=initminer',
       'initminer',
       (SELECT v.voter_name FROM unnest(
          (hafbe_endpoints.get_proposal_votes(1, 100, 'by_proposal_voter', 'asc', 'all')).votes
        ) v)),

    ('get_proposal_votes nested proposal.proposal_id = 9002',
       '9002',
       (SELECT (v.proposal).proposal_id::TEXT FROM unnest(
          (hafbe_endpoints.get_proposal_votes(1, 100, 'by_proposal_voter', 'asc', 'all')).votes
        ) v)),

    ('get_proposal_votes nested proposal carries paid_amount=50000',
       '50000',
       (SELECT (v.proposal).paid_amount FROM unnest(
          (hafbe_endpoints.get_proposal_votes(1, 100, 'by_proposal_voter', 'asc', 'all')).votes
        ) v))
)
SELECT
  name,
  expected,
  COALESCE(actual, '<null>') AS actual,
  CASE WHEN COALESCE(actual, '<null>') = expected THEN 'PASS' ELSE 'FAIL' END AS result
FROM checks;

-- 1) Print the table (FAILs first so they're impossible to miss in CI logs)
SELECT result, name, expected, actual
FROM _hafbe_mock_checks
ORDER BY (result = 'PASS'), name;

-- 2) Fail the script if any check failed; psql -v ON_ERROR_STOP=on then exits
--    non-zero, which propagates through the installer and CI.
DO $$
DECLARE
  _failed_count   INT;
  _failed_summary TEXT;
BEGIN
  SELECT COUNT(*)                                        INTO _failed_count
  FROM _hafbe_mock_checks WHERE result = 'FAIL';

  IF _failed_count > 0 THEN
    SELECT string_agg('  - ' || name || E'\n      expected: ' || expected ||
                      E'\n      actual:   ' || actual, E'\n')
      INTO _failed_summary
    FROM _hafbe_mock_checks WHERE result = 'FAIL';

    RAISE EXCEPTION E'verify.sql: % check(s) failed:\n%', _failed_count, _failed_summary;
  END IF;
END $$;

\echo
\echo 'All checks passed.'
\echo
