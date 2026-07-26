-- =============================================================================
-- Statistics default-window verification (issue #139).
--
-- WHY THIS FILE EXISTS
--   /operation-type-statistics bounds an OMITTED from-block to the most recent
--   hafbe_backend.default_stats_window() (1 year) at daily granularity, because an
--   unbounded daily histogram is ~3,750 periods / ~6.6 MB and trips client timeouts.
--
--   That branch CANNOT be covered by the Tavern suites. The mainnet pattern dataset
--   spans blocks 1..5,000,000 = 2016-03-24..2016-09-15, about 175 days -- less than the
--   window itself -- so GREATEST() always returns the un-clamped lower bound there and
--   the fixtures pin exactly the un-clamped series. Concretely, INVERTING the
--   _from_omitted argument produces byte-identical output on every existing fixture
--   (176 periods for daily_no_range, 36 for change_range), so the arming condition of
--   the clamp is invisible to CI.
--
--   hafbe_backend.aggregation_default_from() is therefore written as a PURE function of
--   its arguments, so it can be asserted directly with synthetic timestamps. These are
--   those assertions. They need no fixture data and run in the mock-data CI job.
--
-- Uses the same PASS/FAIL + RAISE contract as verify.sql, so a failure exits non-zero
-- under psql -v ON_ERROR_STOP=on and fails the pipeline.
-- =============================================================================

\echo
\echo '=== Statistics default-window checks (hafbe_backend.aggregation_default_from) ==='

DROP TABLE IF EXISTS _hafbe_window_checks;

CREATE TEMP TABLE _hafbe_window_checks AS
WITH
-- A mainnet-length span: ~10 years, the situation the fixtures cannot reproduce.
span AS (
  SELECT '2016-03-24 00:00:00'::TIMESTAMP AS genesis_ts,
         '2026-07-26 00:00:00'::TIMESTAMP AS head_ts
),
checks(name, expected, actual) AS (
  VALUES
    -- The window constant itself.
    ('default_stats_window is 1 year',
       '1 year',
       (SELECT hafbe_backend.default_stats_window()::TEXT)),

    -- ARMING CONDITION. These two differ only in _from_omitted and are THE pair no
    -- Tavern fixture can distinguish; inverting the flag flips both.
    ('daily + from-block OMITTED over a 10y span clamps to head minus 1 year',
       '2025-07-26 00:00:00',
       (SELECT hafbe_backend.aggregation_default_from('daily', genesis_ts, head_ts, TRUE)::TEXT FROM span)),

    ('daily + from-block EXPLICIT over a 10y span is honoured in full',
       '2016-03-24 00:00:00',
       (SELECT hafbe_backend.aggregation_default_from('daily', genesis_ts, head_ts, FALSE)::TEXT FROM span)),

    -- Granularity gating: defaulting yearly would collapse the all-time chart to one bar.
    ('monthly + OMITTED is never defaulted',
       '2016-03-24 00:00:00',
       (SELECT hafbe_backend.aggregation_default_from('monthly', genesis_ts, head_ts, TRUE)::TEXT FROM span)),

    ('yearly + OMITTED is never defaulted',
       '2016-03-24 00:00:00',
       (SELECT hafbe_backend.aggregation_default_from('yearly', genesis_ts, head_ts, TRUE)::TEXT FROM span)),

    -- No over-clamping when the chain is younger than the window (the 5M dataset case:
    -- this is the only row the Tavern fixtures also cover, kept here as the boundary).
    ('daily + OMITTED on a chain younger than the window returns genesis',
       '2016-03-24 00:00:00',
       (SELECT hafbe_backend.aggregation_default_from('daily','2016-03-24 00:00:00','2016-09-15 00:00:00', TRUE)::TEXT)),

    ('daily + OMITTED at exactly one year returns genesis (boundary, not off-by-one)',
       '2016-03-24 00:00:00',
       (SELECT hafbe_backend.aggregation_default_from('daily','2016-03-24 00:00:00','2017-03-24 00:00:00', TRUE)::TEXT)),

    -- Resulting series size: the payload bound that motivated the change.
    ('OMITTED daily series over 10y is 366 periods',
       '366',
       (SELECT count(*)::TEXT FROM span, generate_series(
          hafbe_backend.aggregation_default_from('daily', genesis_ts, head_ts, TRUE), head_ts, '1 day'))),

    ('EXPLICIT daily series over 10y keeps every period',
       '3777',
       (SELECT count(*)::TEXT FROM span, generate_series(
          hafbe_backend.aggregation_default_from('daily', genesis_ts, head_ts, FALSE), head_ts, '1 day')))
)
SELECT
  name,
  expected,
  COALESCE(actual, '<null>') AS actual,
  CASE WHEN COALESCE(actual, '<null>') = expected THEN 'PASS' ELSE 'FAIL' END AS result
FROM checks;

SELECT result, name, expected, actual
FROM _hafbe_window_checks
ORDER BY (result = 'PASS'), name;

DO $$
DECLARE
  _failed_count   INT;
  _failed_summary TEXT;
BEGIN
  SELECT COUNT(*) INTO _failed_count
  FROM _hafbe_window_checks WHERE result = 'FAIL';

  IF _failed_count > 0 THEN
    SELECT string_agg('  - ' || name || E'\n      expected: ' || expected ||
                      E'\n      actual:   ' || actual, E'\n')
      INTO _failed_summary
    FROM _hafbe_window_checks WHERE result = 'FAIL';

    RAISE EXCEPTION E'verify_stats_window.sql: % check(s) failed:\n%', _failed_count, _failed_summary;
  END IF;
END $$;

\echo 'All statistics default-window checks passed.'
\echo
