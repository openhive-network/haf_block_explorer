SET ROLE hafbe_owner;

-- ============================================================================
-- Witness Lookup Utilities
-- ============================================================================
-- Functions for looking up witness information by account name.
-- These provide validated witness ID resolution for API endpoints.
--
-- DEPENDENCY CHAIN:
--   get_witness_id() -> validate_witness() -> rest_raise_missing_witness()
-- ============================================================================

/*
 * get_witness_id: Looks up a witness by account name and validates existence.
 *
 * This function combines account lookup with witness validation in a single call.
 * It first resolves the account name to an ID, then validates that the account
 * is actually a registered witness.
 *
 * PARAMETERS:
 *   _account_name - The witness account name to look up
 *
 * RETURNS: The numeric account ID if the witness exists
 *
 * RAISES: Exception via validate_witness() if:
 *   - The account does not exist
 *   - The account is not a registered witness
 *
 * USAGE: Called by witness API endpoints to validate and resolve witness names.
 *
 * EXAMPLE:
 *   SELECT hafbe_backend.get_witness_id('blocktrades');
 *   -- Returns: 17734 (numeric ID)
 *
 *   SELECT hafbe_backend.get_witness_id('nonexistent');
 *   -- Raises: "Witness 'nonexistent' does not exist"
 */
CREATE OR REPLACE FUNCTION hafbe_backend.get_witness_id(_account_name TEXT)
RETURNS INT
LANGUAGE plpgsql
STABLE
AS
$$
DECLARE
  __witness_id INT := (SELECT av.id FROM hive.accounts_view av WHERE av.name = _account_name);
BEGIN
  PERFORM hafbe_backend.validate_witness(__witness_id, _account_name);
  RETURN __witness_id;
END
$$;

/* Numeric Hive software versions have three integer components. Reject malformed
 * or oversized components before casting; callers may supply 0.0.0 for missing
 * versions without treating malformed stored data as a new software release.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.get_witness_version_key(_version TEXT)
RETURNS INT[]
LANGUAGE sql IMMUTABLE
AS
$$
  SELECT CASE
    WHEN _version ~ '^[0-9]{1,9}(\.[0-9]{1,9}){2}$'
      THEN string_to_array(_version, '.')::INT[]
  END;
$$;

/* This replaces the UI's unfiltered highest-version probe. It is the highest
 * observed witness software version, independent of filters and pagination,
 * rather than the protocol version or the release installed on the API node.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.get_current_witness_version()
RETURNS TEXT
LANGUAGE sql STABLE
AS
$$
  SELECT cw.version
  FROM hafbe_app.current_witnesses cw
  WHERE hafbe_backend.get_witness_version_key(cw.version) IS NOT NULL
  ORDER BY hafbe_backend.get_witness_version_key(cw.version) DESC, cw.witness_id DESC
  LIMIT 1;
$$;

/* Resolve the account whose direct witness votes represent this query. Setting
 * a proxy clears the delegating account's own votes, so a query is entirely
 * direct or entirely proxied. Keep the source even when the terminal has no votes.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.get_witness_vote_source(_voter_name TEXT)
RETURNS TABLE(voter_id INT, vote_source TEXT, voted_via TEXT)
LANGUAGE plpgsql STABLE
AS
$$
DECLARE
  __proxy_id INT;
  __seen_ids INT[];
BEGIN
  voter_id := hafah_backend.get_account_id(_voter_name, FALSE);
  IF _voter_name IS NULL THEN
    RETURN NEXT;
    RETURN;
  END IF;

  vote_source := 'direct';
  __seen_ids := ARRAY[voter_id];
  FOR __depth IN 1..4 LOOP
    __proxy_id := (
      SELECT cap.proxy_id
      FROM hafbe_app.current_account_proxies cap
      WHERE cap.account_id = voter_id
    );
    EXIT WHEN __proxy_id IS NULL;
    IF __proxy_id = ANY(__seen_ids) THEN
      RAISE EXCEPTION 'Witness proxy chain contains a cycle';
    END IF;
    voter_id := __proxy_id;
    vote_source := 'proxy';
    __seen_ids := array_append(__seen_ids, voter_id);
  END LOOP;

  IF EXISTS (
    SELECT 1 FROM hafbe_app.current_account_proxies cap
    WHERE cap.account_id = voter_id
  ) THEN
    RAISE EXCEPTION 'Witness proxy chain exceeds 4 levels';
  END IF;
  IF vote_source = 'proxy' THEN
    voted_via := (SELECT av.name FROM hive.accounts_view av WHERE av.id = voter_id);
  END IF;
  RETURN NEXT;
END
$$;

/* One relation supplies both the list and its count. The vote predicate uses
 * weight rather than voter count, including zero-weight votes in has-votes=false.
 * strpos makes the name filter literal: percent and underscore are not wildcards.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.get_filtered_witness_ids(
    _voter_id     INT = NULL,
    _witness_name TEXT = NULL,
    _has_votes    BOOLEAN = NULL,
    _is_disabled  BOOLEAN = NULL
)
RETURNS TABLE(witness_id INT)
LANGUAGE sql STABLE
AS
$$
  SELECT cw.witness_id
  FROM hafbe_app.current_witnesses cw
  JOIN hive.accounts_view av ON av.id = cw.witness_id
  JOIN hafbe_app.witness_rank_cache wr ON wr.witness_id = cw.witness_id
  LEFT JOIN hafbe_app.witness_votes_cache wv ON wv.witness_id = cw.witness_id
  WHERE (_voter_id IS NULL OR EXISTS (
      SELECT 1 FROM hafbe_app.current_witness_votes cwv
      WHERE cwv.voter_id = _voter_id AND cwv.witness_id = cw.witness_id
    ))
    AND (_witness_name IS NULL OR strpos(av.name, _witness_name) > 0)
    AND (_has_votes IS NULL OR (COALESCE(wv.votes, 0) > 0) = _has_votes)
    AND (_is_disabled IS NULL OR (
      COALESCE(cw.signing_key, '') = 'STM1111111111111111111111111111111114T1Anm'
    ) = _is_disabled);
$$;

/* Rank enabled witnesses over the complete rank cache before any user filters.
 * Disabled witnesses have no real_rank; their original rank remains available.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.get_witness_real_ranks()
RETURNS TABLE(witness_id INT, real_rank INT)
LANGUAGE sql STABLE
AS
$$
  SELECT cw.witness_id,
    CASE WHEN COALESCE(cw.signing_key, '') <> 'STM1111111111111111111111111111111114T1Anm' THEN
      (COUNT(*) FILTER (
        WHERE COALESCE(cw.signing_key, '') <> 'STM1111111111111111111111111111111114T1Anm'
      ) OVER (ORDER BY wr.rank ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW))::INT
    END
  FROM hafbe_app.current_witnesses cw
  JOIN hafbe_app.witness_rank_cache wr ON wr.witness_id = cw.witness_id;
$$;

RESET ROLE;
