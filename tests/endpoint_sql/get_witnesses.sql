-- Run only against a fresh, isolated PostgreSQL database:
-- psql -X -v ON_ERROR_STOP=1 -f tests/endpoint_sql/get_witnesses.sql
-- The transaction creates the external HAF interfaces and cache fixtures, loads
-- the real application SQL, checks its API contract, then removes every object.
BEGIN;
SET plpgsql.check_asserts = on;
CREATE ROLE hafbe_owner;
CREATE SCHEMA hafbe_backend AUTHORIZATION hafbe_owner;
CREATE SCHEMA hafbe_app AUTHORIZATION hafbe_owner;
CREATE SCHEMA hafbe_endpoints AUTHORIZATION hafbe_owner;
CREATE SCHEMA hive AUTHORIZATION hafbe_owner;
CREATE SCHEMA hafah_backend AUTHORIZATION hafbe_owner;
SET ROLE hafbe_owner;
CREATE TYPE hive.blocks_range AS (first_block INT, last_block INT);

-- Stand-ins for the HAF account view and HAFBE's already processed cache tables.
CREATE TABLE hive.accounts_view (id INT PRIMARY KEY, name TEXT UNIQUE NOT NULL);
CREATE TABLE hafbe_app.current_witnesses (
  witness_id INT PRIMARY KEY, url TEXT, price_feed FLOAT, bias NUMERIC,
  feed_updated_at TIMESTAMP, block_size INT, signing_key TEXT, version TEXT,
  hbd_interest_rate INT, last_created_block_num INT, account_creation_fee INT,
  missed_blocks INT
);
CREATE TABLE hafbe_app.witness_rank_cache (witness_id INT PRIMARY KEY, rank INT);
CREATE TABLE hafbe_app.witness_votes_cache (witness_id INT PRIMARY KEY, votes BIGINT, voters_num INT);
CREATE TABLE hafbe_app.witness_votes_change_cache (
  witness_id INT PRIMARY KEY, votes_daily_change BIGINT, voters_num_daily_change INT
);
CREATE TABLE hafbe_app.current_witness_votes (voter_id INT, witness_id INT, source_op BIGINT);
CREATE TABLE hafbe_app.current_account_proxies (account_id INT PRIMARY KEY, proxy_id INT, source_op BIGINT);

-- External hafah interfaces: account identity and envelope pagination only.
CREATE FUNCTION hafah_backend.get_account_id(_name TEXT, _required BOOLEAN)
RETURNS INT LANGUAGE plpgsql STABLE AS $$
DECLARE _id INT;
BEGIN
  SELECT id INTO _id FROM hive.accounts_view WHERE name = _name;
  IF _id IS NULL AND (_required OR _name IS NOT NULL) THEN
    RAISE EXCEPTION 'Account does not exist: %', _name;
  END IF;
  RETURN _id;
END
$$;
CREATE FUNCTION hafah_backend.total_pages(_count BIGINT, _page_size INT)
RETURNS INT LANGUAGE SQL IMMUTABLE AS $$
  SELECT CEIL(_count::NUMERIC / _page_size)::INT
$$;
RESET ROLE;

\ir ../../endpoints/types/enums.sql
\ir ../../endpoints/types/witnesses.sql
\ir ../../backend/utilities/validators.sql
\ir ../../backend/utilities/witness.sql
\ir ../../backend/endpoint_helpers/witness.sql
\ir ../../endpoints/witnesses/get_witnesses.sql
\ir ../../endpoints/witnesses/get_witness.sql

SET ROLE hafbe_owner;
INSERT INTO hive.accounts_view VALUES
  (1, 'alpha'), (2, 'beta'), (3, 'gamma'), (4, 'delta'), (5, 'omega'),
  (6, 'per%cent'), (7, 'under_score'),
  (101, 'direct'), (102, 'proxy-one'), (103, 'proxy-four'), (104, 'hop-one'),
  (105, 'hop-two'), (106, 'hop-three'), (107, 'proxy-empty'), (108, 'no-votes');
INSERT INTO hafbe_app.current_witnesses
  (witness_id, signing_key, version, missed_blocks, hbd_interest_rate, last_created_block_num, account_creation_fee)
VALUES
  (1, 'enabled-alpha', '1.27.3', 9, 1000, 100, 100),
  (2, 'STM1111111111111111111111111111111114T1Anm', '1.27.10', 9, 1000, 100, 100),
  (3, 'enabled-gamma', '1.27.11', 4, 500, 300, 300),
  (4, 'enabled-delta', '1.28.7', 4, 500, 300, 300),
  (5, 'STM1111111111111111111111111111111114T1Anm', '1.28.10', 20, 2000, 200, 200),
  (6, 'enabled-percent', '1.27.3', 0, 0, 0, 50),
  (7, NULL, '1.27.3', 0, 0, 0, 50);
INSERT INTO hafbe_app.witness_rank_cache VALUES (1, 1), (2, 2), (3, 3), (4, 4), (5, 5), (6, 6), (7, 7);
-- A witness can have zero voting weight while still having voters. Witness 7
-- intentionally has no vote-cache row, exercising the zero-weight default.
INSERT INTO hafbe_app.witness_votes_cache VALUES
  (1, 500, 2), (2, 400, 2), (3, 300, 1), (4, 200, 1), (5, 100, 1), (6, 0, 3);
INSERT INTO hafbe_app.current_witness_votes VALUES (101, 1, 1), (101, 3, 2), (101, 6, 3);
INSERT INTO hafbe_app.current_account_proxies VALUES
  (102, 101, 1), (103, 104, 2), (104, 105, 3), (105, 106, 4), (106, 101, 5), (107, 108, 6);
RESET ROLE;

-- Read names in the endpoint's returned order; expected orders below are fixed
-- business examples, not reimplementations of the production ordering query.
CREATE FUNCTION pg_temp.witness_names(_response hafbe_backend.witnesses_return)
RETURNS TEXT[] LANGUAGE SQL AS $$
  SELECT COALESCE(array_agg(w.witness_name ORDER BY w.ordinality), ARRAY[]::TEXT[])
  FROM unnest(_response.witnesses) WITH ORDINALITY AS w
$$;

DO $$
DECLARE
  r hafbe_backend.witnesses_return;
  w hafbe_backend.witness;
  sort_key hafbe_backend.order_by_witness;
  direction hafbe_backend.sort_direction;
  expected_names TEXT[];
  rejected BOOLEAN;
BEGIN
  r := hafbe_endpoints.get_witnesses("sort" => 'version', "direction" => 'asc');
  ASSERT pg_temp.witness_names(r) = ARRAY['alpha', 'per%cent', 'under_score', 'beta', 'gamma', 'delta', 'omega'],
    'Version ascending must order numeric patch components, then stable witness IDs';
  r := hafbe_endpoints.get_witnesses("sort" => 'version', "direction" => 'desc');
  ASSERT pg_temp.witness_names(r) = ARRAY['omega', 'delta', 'gamma', 'beta', 'under_score', 'per%cent', 'alpha'],
    'Version descending must prefer 1.28.10 over 1.28.7 and 1.27.11 over 1.27.3';

  r := hafbe_endpoints.get_witnesses("witness-name" => 'alpha', "has-votes" => TRUE, "is-disabled" => FALSE);
  ASSERT r.current_version = '1.28.10', 'Current version must remain global, including disabled witnesses';
  ASSERT r.total_witnesses = 1 AND r.total_pages = 1, 'Combined filters must count their intersection';
  w := r.witnesses[1];
  ASSERT w.rank = 1 AND w.real_rank = 1, 'Enabled global rank must be present on every list row';

  r := hafbe_endpoints.get_witnesses("is-disabled" => TRUE, "sort" => 'rank', "direction" => 'asc');
  ASSERT pg_temp.witness_names(r) = ARRAY['beta', 'omega'], 'Disabled filter must match the exact null signing key';
  ASSERT (r.witnesses[1]).real_rank IS NULL AND (r.witnesses[2]).real_rank IS NULL,
    'Disabled witnesses have no enabled rank';
  r := hafbe_endpoints.get_witnesses("is-disabled" => FALSE, "sort" => 'rank', "direction" => 'asc');
  ASSERT pg_temp.witness_names(r) = ARRAY['alpha', 'gamma', 'delta', 'per%cent', 'under_score'],
    'NULL signing key must not be confused with the protocol null signing key';
  r := hafbe_endpoints.get_witnesses("is-disabled" => NULL, "witness-name" => '');
  ASSERT r.total_witnesses = 7, 'NULL disabled and empty name filters must leave the set unfiltered';

  r := hafbe_endpoints.get_witnesses("has-votes" => TRUE, "sort" => 'rank', "direction" => 'asc');
  ASSERT pg_temp.witness_names(r) = ARRAY['alpha', 'beta', 'gamma', 'delta', 'omega'],
    'Has-votes means positive voting weight, not voter count';
  r := hafbe_endpoints.get_witnesses("has-votes" => FALSE, "sort" => 'rank', "direction" => 'asc');
  ASSERT pg_temp.witness_names(r) = ARRAY['per%cent', 'under_score'],
    'Zero-weight voters and missing cache rows must both count as no voting weight';

  r := hafbe_endpoints.get_witnesses("witness-name" => 'ta', "sort" => 'rank', "direction" => 'asc');
  ASSERT pg_temp.witness_names(r) = ARRAY['beta', 'delta'], 'Witness name search must match an interior substring';
  r := hafbe_endpoints.get_witnesses("witness-name" => '%');
  ASSERT pg_temp.witness_names(r) = ARRAY['per%cent'], 'Percent in witness search must be literal';
  r := hafbe_endpoints.get_witnesses("witness-name" => '_');
  ASSERT pg_temp.witness_names(r) = ARRAY['under_score'], 'Underscore in witness search must be literal';

  r := hafbe_endpoints.get_witnesses("voter-name" => 'direct', "sort" => 'rank', "direction" => 'asc');
  ASSERT pg_temp.witness_names(r) = ARRAY['alpha', 'gamma', 'per%cent'], 'Direct voter must return its own approval set';
  ASSERT r.vote_source = 'direct' AND r.voted_via IS NULL, 'Direct votes need direct provenance';
  r := hafbe_endpoints.get_witnesses("voter-name" => 'proxy-one', "sort" => 'rank', "direction" => 'asc');
  ASSERT pg_temp.witness_names(r) = ARRAY['alpha', 'gamma', 'per%cent'], 'One-hop proxy must follow its voting account';
  ASSERT r.vote_source = 'proxy' AND r.voted_via = 'direct', 'Proxy provenance must name the voting account';
  r := hafbe_endpoints.get_witnesses("voter-name" => 'proxy-four', "sort" => 'rank', "direction" => 'asc');
  ASSERT pg_temp.witness_names(r) = ARRAY['alpha', 'gamma', 'per%cent'], 'Four-hop governance proxy must be supported';
  ASSERT r.vote_source = 'proxy' AND r.voted_via = 'direct', 'Four-hop provenance must name the terminal voter';
  r := hafbe_endpoints.get_witnesses("voter-name" => 'proxy-empty');
  ASSERT r.total_witnesses = 0 AND r.total_pages = 0 AND cardinality(r.witnesses) = 0,
    'A proxy whose terminal account has no votes must produce an empty envelope';
  ASSERT r.vote_source = 'proxy' AND r.voted_via = 'no-votes' AND r.current_version = '1.28.10',
    'An empty approval set must retain provenance and the global current version';
  r := hafbe_endpoints.get_witnesses();
  ASSERT r.vote_source IS NULL AND r.voted_via IS NULL, 'Unfiltered listing has no voter provenance';

  r := hafbe_endpoints.get_witnesses("page" => 2, "page-size" => 1, "voter-name" => 'proxy-one',
    "has-votes" => TRUE, "is-disabled" => FALSE, "sort" => 'witness', "direction" => 'asc');
  ASSERT r.total_witnesses = 2 AND r.total_pages = 2 AND pg_temp.witness_names(r) = ARRAY['gamma'],
    'Pagination and counts must use all composed filters';
  ASSERT (r.witnesses[1]).rank = 3 AND (r.witnesses[1]).real_rank = 2,
    'Real rank must count globally enabled witnesses before voter/name filters, sorting and pagination';
  r := hafbe_endpoints.get_witnesses("witness-name" => 'gamma', "sort" => 'version', "direction" => 'desc');
  ASSERT (r.witnesses[1]).real_rank = 2, 'A singleton search must preserve the global enabled rank';
  r := hafbe_endpoints.get_witnesses("witness-name" => 'no-match');
  ASSERT r.total_witnesses = 0 AND r.total_pages = 0 AND cardinality(r.witnesses) = 0
    AND r.current_version = '1.28.10', 'Empty search must retain a valid global envelope';

  FOREACH sort_key IN ARRAY ARRAY['missed_blocks', 'hbd_interest_rate', 'last_confirmed_block_num', 'account_creation_fee']::hafbe_backend.order_by_witness[] LOOP
    FOREACH direction IN ARRAY ARRAY['asc', 'desc']::hafbe_backend.sort_direction[] LOOP
      IF sort_key IN ('missed_blocks', 'hbd_interest_rate') THEN
        expected_names := CASE direction WHEN 'asc'
          THEN ARRAY['per%cent', 'under_score', 'gamma', 'delta', 'alpha', 'beta', 'omega']
          ELSE ARRAY['omega', 'beta', 'alpha', 'delta', 'gamma', 'under_score', 'per%cent'] END;
      ELSE
        expected_names := CASE direction WHEN 'asc'
          THEN ARRAY['per%cent', 'under_score', 'alpha', 'beta', 'omega', 'gamma', 'delta']
          ELSE ARRAY['delta', 'gamma', 'omega', 'beta', 'alpha', 'under_score', 'per%cent'] END;
      END IF;
      r := hafbe_endpoints.get_witnesses("sort" => sort_key, "direction" => direction);
      ASSERT pg_temp.witness_names(r) = expected_names,
        format('Numeric sort %s %s must preserve stable direction-specific ties', sort_key, direction);
    END LOOP;
  END LOOP;

  -- Exercise the real single-witness endpoint and its helper, which share the extended type.
  w := hafbe_endpoints.get_witness('gamma');
  ASSERT w.witness_name = 'gamma' AND w.rank = 3 AND w.real_rank = 2,
    'Single-witness helper must populate the new field without shifting existing composite fields';
  ASSERT w.version = '1.27.11' AND w.missed_blocks = 4 AND w.account_creation_fee = 300,
    'Extending the shared witness type must preserve its existing fields';

  rejected := FALSE;
  BEGIN
    PERFORM hafbe_endpoints.get_witnesses("voter-name" => '');
  EXCEPTION WHEN raise_exception THEN
    rejected := TRUE;
  END;
  ASSERT rejected, 'Empty voter name must use existing invalid-account behavior';
  rejected := FALSE;
  BEGIN
    PERFORM hafbe_endpoints.get_witnesses("voter-name" => 'missing');
  EXCEPTION WHEN raise_exception THEN
    rejected := TRUE;
  END;
  ASSERT rejected, 'Missing voter name must use existing invalid-account behavior';
END
$$;

-- Historical malformed or absent software versions must not turn a listing
-- into a cast error or replace the global numeric maximum.
UPDATE hafbe_app.current_witnesses SET version = '9999999999.0.0' WHERE witness_id = 5;
DO $$
DECLARE r hafbe_backend.witnesses_return;
BEGIN
  ASSERT hafbe_backend.get_witness_version_key('9999999999.0.0') IS NULL,
    'An oversized version component must not overflow its numeric key';
  r := hafbe_endpoints.get_witnesses("sort" => 'version', "direction" => 'desc');
  ASSERT r.current_version = '1.28.7' AND pg_temp.witness_names(r)
    = ARRAY['delta', 'gamma', 'beta', 'under_score', 'per%cent', 'alpha', 'omega'],
    'A malformed stored version must sort last and not override the current version';
  r := hafbe_endpoints.get_witnesses("sort" => 'version', "direction" => 'asc');
  ASSERT pg_temp.witness_names(r)
    = ARRAY['alpha', 'per%cent', 'under_score', 'beta', 'gamma', 'delta', 'omega'],
    'A malformed version must also sort last ascending';
END
$$;
UPDATE hafbe_app.current_witnesses SET version = NULL WHERE witness_id = 5;
DO $$
DECLARE r hafbe_backend.witnesses_return;
BEGIN
  r := hafbe_endpoints.get_witnesses("sort" => 'version', "direction" => 'asc');
  ASSERT r.current_version = '1.28.7' AND (r.witnesses[1]).witness_name = 'omega'
    AND (r.witnesses[1]).version = '0.0.0',
    'An absent version must retain the existing zero-version display fallback';
END
$$;
ROLLBACK;
