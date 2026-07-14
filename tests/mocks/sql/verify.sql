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
--   - proposal 9003 created by gtg (active at block time 2025-06-01, no votes)
--   - proposal 9004 created by blocktrades (expired at block time 2025-06-01)
--
-- Status at block time 2025-06-01T00:00:15 (block 91000006):
--   9002: start=2025-07-01 > now  -> inactive
--   9003: start=2025-01-01 <= now -> active
--   9004: end=2020-06-01 < now    -> expired
--
-- Expected final state:
--   current_proposals:           9001 removed=TRUE / 9002,9003,9004 removed=FALSE
--   current_proposal_votes:      ONE row: (initminer, 9002)
--   proposal_payments:           ONE row: (9002, 50000)
--   proposal_votes_history:      9 rows total:
--                                  5 TRUE inserts
--                                  2 FALSE from steem declined voting rights (9001, 9002)
--                                  2 FALSE from remove_proposal 9001 (dan, initminer)
--   proposal_vote_stats_cache:   ONE row for 9002, voters_num=1, total_votes=5000000
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
       '4',
       (SELECT COUNT(*)::TEXT FROM hafbe_app.current_proposals
        WHERE proposal_id IN (9001, 9002, 9003, 9004))),

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

    ('proposal_votes_history count = 9 (5 TRUE + 2 decline FALSE + 2 remove FALSE)',
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

    -- Stake math: verify_mock_data.sh seeds initminer with 5000000 vests so this
    -- catches proxy-exclusion bugs or a broken SUM that silently yields 0.
    ('proposal_vote_stats_cache 9002 total_votes = 5000000 (seeded initminer vests)',
       '5000000',
       (SELECT total_votes::TEXT FROM hafbe_app.proposal_vote_stats_cache
        WHERE proposal_id = 9002)),

    -- ----- Endpoint-level assertions -----
    -- Catch composition bugs that table-level checks above cannot: removed
    -- filter, paid_amount join, voters_num/total_votes wiring, nested
    -- proposal composite in /proposals/votes.

    ('get_proposals.total_proposals excludes removed (= 3, not 4)',
       '3',
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
        ) v)),

    -- ----- Status filter assertions -----

    ('get_proposals status=active returns 1 (only 9003)',
       '1',
       (SELECT (hafbe_endpoints.get_proposals(1, 100, 'by_total_votes', 'desc', 'active')).total_proposals::TEXT)),

    ('get_proposals status=active proposal_id = 9003',
       '9003',
       (SELECT p.proposal_id::TEXT FROM unnest(
          (hafbe_endpoints.get_proposals(1, 100, 'by_total_votes', 'desc', 'active')).proposals
        ) p LIMIT 1)),

    ('get_proposals status=inactive returns 1 (only 9002)',
       '1',
       (SELECT (hafbe_endpoints.get_proposals(1, 100, 'by_total_votes', 'desc', 'inactive')).total_proposals::TEXT)),

    ('get_proposals status=expired returns 1 (only 9004)',
       '1',
       (SELECT (hafbe_endpoints.get_proposals(1, 100, 'by_total_votes', 'desc', 'expired')).total_proposals::TEXT)),

    ('get_proposals status=expired proposal_id = 9004',
       '9004',
       (SELECT p.proposal_id::TEXT FROM unnest(
          (hafbe_endpoints.get_proposals(1, 100, 'by_total_votes', 'desc', 'expired')).proposals
        ) p LIMIT 1)),

    ('get_proposals status=votable returns 2 (active 9003 + inactive 9002)',
       '2',
       (SELECT (hafbe_endpoints.get_proposals(1, 100, 'by_total_votes', 'desc', 'votable')).total_proposals::TEXT)),

    -- ----- Sort order assertions -----
    -- by_total_votes: 9002 has 5000000 (seeded), 9003+9004 have 0.
    -- Tie-break for direction=desc is proposal_id DESC: 9004 > 9003.

    ('get_proposals by_total_votes desc: first = 9002 (highest votes)',
       '9002',
       (SELECT p.proposal_id::TEXT FROM unnest(
          (hafbe_endpoints.get_proposals(1, 100, 'by_total_votes', 'desc', 'all')).proposals
        ) p LIMIT 1)),

    ('get_proposals by_total_votes desc pagination: page 2 size 1 = 9004',
       '9004',
       (SELECT p.proposal_id::TEXT FROM unnest(
          (hafbe_endpoints.get_proposals(2, 1, 'by_total_votes', 'desc', 'all')).proposals
        ) p LIMIT 1)),

    ('get_proposals by_total_votes asc: first = 9003 (0 votes, lowest proposal_id tie-break)',
       '9003',
       (SELECT p.proposal_id::TEXT FROM unnest(
          (hafbe_endpoints.get_proposals(1, 100, 'by_total_votes', 'asc', 'all')).proposals
        ) p LIMIT 1)),

    -- by_creator: 9002+9004 creator=blocktrades < 9003 creator=gtg.
    -- Tie between 9002 and 9004 (same creator): broken by proposal_id ASC (direction=asc).

    ('get_proposals by_creator asc: first = 9002 (blocktrades, smallest id)',
       '9002',
       (SELECT p.proposal_id::TEXT FROM unnest(
          (hafbe_endpoints.get_proposals(1, 100, 'by_creator', 'asc', 'all')).proposals
        ) p LIMIT 1)),

    ('get_proposals by_creator desc: first = 9003 (gtg > blocktrades)',
       '9003',
       (SELECT p.proposal_id::TEXT FROM unnest(
          (hafbe_endpoints.get_proposals(1, 100, 'by_creator', 'desc', 'all')).proposals
        ) p LIMIT 1)),

    -- by_end_date asc: 9004 (2020-06-01) < 9003 (2099-06-30) < 9002 (2099-12-31)

    ('get_proposals by_end_date asc: first = 9004 (earliest end)',
       '9004',
       (SELECT p.proposal_id::TEXT FROM unnest(
          (hafbe_endpoints.get_proposals(1, 100, 'by_end_date', 'asc', 'all')).proposals
        ) p LIMIT 1)),

    ('get_proposals by_end_date desc: first = 9002 (latest end)',
       '9002',
       (SELECT p.proposal_id::TEXT FROM unnest(
          (hafbe_endpoints.get_proposals(1, 100, 'by_end_date', 'desc', 'all')).proposals
        ) p LIMIT 1)),

    -- ----- get_proposal_votes_history stake sourcing (#140) -----
    -- The tavern patterns alone CANNOT prove the expired-view fallback fired: if steem
    -- happened to hold 0 vests, a working fallback and a fallback broken back to
    -- COALESCE(..., 0) would emit byte-identical JSON. These checks are value-independent
    -- (they compare against the view, not a literal) and so stay honest either way.

    -- steem lost every vote to the declined_voting_rights cascade, so it is in none of the
    -- three tracked_accounts legs -> it MUST be a genuine cache miss. If this ever starts
    -- failing, the two checks below stop testing the fallback branch at all.
    ('vote-history: steem is absent from account_vest_stats_cache (cache-miss branch)',
       '0',
       (SELECT COUNT(*)::TEXT FROM hafbe_app.account_vest_stats_cache
        WHERE account_id = (SELECT id FROM hive.accounts_view WHERE name = 'steem'))),

    -- ...and its reported stake must equal expired_voter_stats_view exactly, AND be
    -- non-zero (a zero here would make the assertion vacuous).
    ('vote-history: steem stake == expired_voter_stats_view, and non-zero',
       'true',
       (SELECT bool_and(
                 v.voter_vests   = e.vests::TEXT         AND
                 v.direct_vests  = e.account_vests::TEXT AND
                 v.proxied_vests = e.proxied_vests::TEXT AND
                 e.vests > 0
               )::TEXT
        FROM unnest((hafbe_endpoints.get_proposal_votes_history(9002, 'steem')).votes_history) v
        CROSS JOIN hafbe_backend.expired_voter_stats_view e
        WHERE e.account_id = (SELECT id FROM hive.accounts_view WHERE name = 'steem'))),

    -- Both of steem's rows (approve + withdrawal) must carry the SAME stake: the source is
    -- chosen per voter, never per row. The row count is asserted too, otherwise a regression
    -- that returned only ONE steem row would still show a single distinct stake and pass.
    ('vote-history: steem has 2 rows, both carrying identical stake',
       '2|1',
       (SELECT COUNT(*)::TEXT || '|' ||
               COUNT(DISTINCT (v.voter_vests, v.direct_vests, v.proxied_vests))::TEXT
        FROM unnest((hafbe_endpoints.get_proposal_votes_history(9002, 'steem')).votes_history) v)),

    -- Cache-hit branch: initminer is still a current voter, and verify_mock_data.sh seeds
    -- its cache row to a deterministic 5000000.
    ('vote-history: initminer voter_vests = 5000000 (cache-hit branch), no proxy',
       '5000000|',
       (SELECT v.voter_vests || '|' || v.proxy
        FROM unnest((hafbe_endpoints.get_proposal_votes_history(9002, 'initminer')).votes_history) v
        LIMIT 1)),

    -- Tie-break regression guard. On 9001, initminer approves at block 91000004 and the
    -- remove_proposal cascade writes its synthetic approve=FALSE row in the SAME block, so
    -- (source_op_block, voter_id) ties. Without source_op as the final sort key the
    -- withdrawal can be returned BEFORE the approval; asc order must be TRUE then FALSE.
    ('vote-history: 9001 initminer same-block approve precedes its withdrawal',
       'true|false',
       (SELECT string_agg(t.approve::TEXT, '|' ORDER BY t.ord)
        FROM unnest((hafbe_endpoints.get_proposal_votes_history(9001, 'initminer', 1, 100, 'asc')).votes_history)
             WITH ORDINALITY AS t(voter_name, approve, voter_vests, direct_vests, proxied_vests, proxy, ts, ord))),

    -- ...and desc must be the exact reverse.
    ('vote-history: 9001 initminer desc is the exact reverse',
       'false|true',
       (SELECT string_agg(t.approve::TEXT, '|' ORDER BY t.ord)
        FROM unnest((hafbe_endpoints.get_proposal_votes_history(9001, 'initminer', 1, 100, 'desc')).votes_history)
             WITH ORDINALITY AS t(voter_name, approve, voter_vests, direct_vests, proxied_vests, proxy, ts, ord))),

    -- The documented contract is a ONE-WAY implication: a proxied voter must report 0.
    -- Do NOT assert the converse (voter_vests = 0 => proxied): a voter holding no VESTS
    -- legitimately reports '0' with an empty proxy, which would fail a biconditional check.
    ('vote-history: proxied voter => voter_vests = 0',
       'true',
       (SELECT bool_and(v.proxy = '' OR v.voter_vests = '0')::TEXT
        FROM unnest((hafbe_endpoints.get_proposal_votes_history(9002)).votes_history) v))
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
