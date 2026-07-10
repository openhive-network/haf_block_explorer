SET ROLE hafbe_owner;

-- ============================================================================
-- Validation Functions
-- ============================================================================
-- Functions that validate input parameters and business rules for API endpoints.
-- Each function checks a specific condition and raises an exception (via
-- functions in exceptions.sql) if the validation fails.
--
-- PATTERN:
--   - Functions return VOID on success
--   - Functions raise EXCEPTION on failure
--   - Called at the start of API endpoint functions to validate inputs
--
-- NOTE: Exception-raising functions are in exceptions.sql. This file contains
-- only the validation logic that determines when to raise exceptions.
-- ============================================================================

-- ============================================================================
-- Pagination Validators
-- ============================================================================

/*
 * validate_limit: Validates that a page size does not exceed the maximum allowed.
 *
 * PARAMETERS:
 *   _given_limit    - The page size requested by the user
 *   _expected_limit - The maximum allowed page size
 *   _given_limit_name - Name of the parameter for error message (default: 'page-size')
 *
 * RAISES: Exception if given_limit > expected_limit
 *
 * USAGE: Called at the start of paginated endpoints to prevent excessive data retrieval.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.validate_limit(
    _given_limit      BIGINT,
    _expected_limit   INT,
    _given_limit_name TEXT DEFAULT 'page-size'
)
RETURNS VOID
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
BEGIN
  -- An explicit NULL (e.g. {"page-size": null} over PostgREST) must be rejected here,
  -- not silently pass: `NULL > _expected_limit` is NULL (not TRUE), so without this guard
  -- the value flows on to `LIMIT NULL` (= "no limit") and returns the whole table,
  -- bypassing the cap. Endpoints that want a default should COALESCE before validating.
  IF _given_limit IS NULL THEN
    RAISE EXCEPTION '% must not be null', _given_limit_name;
  END IF;
  IF _given_limit > _expected_limit THEN
    RAISE EXCEPTION '% <= %: % of % is greater than maxmimum allowed',
      _given_limit_name, _expected_limit, _given_limit_name, _given_limit;
  END IF;
END
$$;

/*
 * validate_negative_limit: Validates that a page size is positive.
 *
 * PARAMETERS:
 *   _given_limit      - The page size requested by the user
 *   _given_limit_name - Name of the parameter for error message (default: 'page-size')
 *
 * RAISES: Exception if given_limit <= 0
 *
 * USAGE: Called at the start of paginated endpoints to ensure positive page size.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.validate_negative_limit(
    _given_limit      BIGINT,
    _given_limit_name TEXT DEFAULT 'page-size'
)
RETURNS VOID
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
BEGIN
  -- NULL is not positive: reject it (NULL <= 0 is NULL, not TRUE) so it cannot slip
  -- through to LIMIT NULL. See validate_limit for the full rationale.
  IF _given_limit IS NULL THEN
    RAISE EXCEPTION '% must not be null', _given_limit_name;
  END IF;
  IF _given_limit <= 0 THEN
    RAISE EXCEPTION '% <= 0: % of % is lesser or equal 0',
      _given_limit_name, _given_limit_name, _given_limit;
  END IF;
END
$$;

/*
 * validate_page: Validates that a page number does not exceed the maximum page.
 *
 * PARAMETERS:
 *   _given_page - The page number requested by the user
 *   _max_page   - The maximum valid page number
 *
 * RAISES: Exception if given_page > max_page (unless given_page = 1)
 *
 * NOTE: Page 1 is always valid, even when max_page = 0 (empty result set).
 *
 * USAGE: Called after calculating total pages to validate requested page.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.validate_page(
    _given_page BIGINT,
    _max_page   INT
)
RETURNS VOID
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
BEGIN
  IF _given_page > _max_page AND _given_page != 1 THEN
    RAISE EXCEPTION 'page <= %: page of % is greater than maxmimum page',
      _max_page, _given_page;
  END IF;
END
$$;

/*
 * validate_negative_page: Validates that a page number is positive.
 *
 * PARAMETERS:
 *   _given_page - The page number requested by the user
 *
 * RAISES: Exception if given_page <= 0
 *
 * USAGE: Called at the start of paginated endpoints to ensure positive page number.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.validate_negative_page(_given_page BIGINT)
RETURNS VOID
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
BEGIN
  IF _given_page <= 0 THEN
    RAISE EXCEPTION 'page <= 0: page of % is lesser or equal 0', _given_page;
  END IF;
END
$$;

-- ============================================================================
-- Entity Validators
-- ============================================================================

/*
 * validate_witness: Validates that an account is a registered witness.
 *
 * PARAMETERS:
 *   _account_id   - The numeric account ID to check
 *   _account_name - The account name (for error message)
 *
 * RAISES: Exception via rest_raise_missing_witness() if the account is not
 *         found in hafbe_app.current_witnesses.
 *
 * USAGE: Called by hafbe_backend.get_witness_id() before returning witness data.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.validate_witness(
    _account_id   INT,
    _account_name TEXT
)
RETURNS VOID
LANGUAGE 'plpgsql'
STABLE
AS
$$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM hafbe_app.current_witnesses WHERE witness_id = _account_id) THEN
    PERFORM hafbe_backend.rest_raise_missing_witness(_account_name);
  END IF;
END
$$;

-- ============================================================================
-- Block Validators
-- ============================================================================

/*
 * validate_block_num_too_high: Validates that a block number does not exceed
 * the current head block.
 *
 * PARAMETERS:
 *   _first_block   - The requested block number (may be NULL)
 *   _current_block - The current head block number
 *
 * RAISES: Exception via raise_block_num_too_high_exception() if first_block
 *         exists and exceeds current_block.
 *
 * NOTE: NULL _first_block is valid (will use defaults). Only validates when
 *       an explicit block number is provided.
 *
 * USAGE: Called before processing block range queries.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.validate_block_num_too_high(
    _first_block   INT,
    _current_block INT
)
RETURNS VOID
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
BEGIN
  IF _first_block IS NOT NULL AND _current_block < _first_block THEN
    PERFORM hafbe_backend.raise_block_num_too_high_exception(_first_block::NUMERIC, _current_block);
  END IF;
END
$$;

-- ============================================================================
-- Index Validators
-- ============================================================================

/*
 * validate_comment_search_indexes: Validates that comment search indexes are
 * installed and ready for use.
 *
 * RAISES: Exception if hafbe_app.isCommentSearchIndexesCreated() returns FALSE.
 *
 * USAGE: Called at the start of comment search endpoints.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.validate_comment_search_indexes()
RETURNS VOID
LANGUAGE 'plpgsql'
STABLE
AS
$$
BEGIN
  IF NOT hafbe_app.isCommentSearchIndexesCreated() THEN
    RAISE EXCEPTION 'Comment search indexes are not installed';
  END IF;
END
$$;

/*
 * validate_block_search_indexes: Validates that block search indexes are
 * installed and ready for use.
 *
 * RAISES: Exception if hafbe_app.isBlockSearchIndexesCreated() returns FALSE.
 *
 * USAGE: Called at the start of block search endpoints.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.validate_block_search_indexes()
RETURNS VOID
LANGUAGE 'plpgsql'
STABLE
AS
$$
BEGIN
  IF NOT hafbe_app.isBlockSearchIndexesCreated() THEN
    RAISE EXCEPTION 'Block search indexes are not installed';
  END IF;
END
$$;

-- ============================================================================
-- Operation Type Validators
-- ============================================================================

/*
 * validate_path_filter_keys: Validates that provided JSON path filter keys
 * are valid for the specified operation types.
 *
 * PARAMETERS:
 *   _operation_types - Array of operation type IDs to validate keys against
 *   _set_of_keys     - JSON array of key names provided by the user
 *
 * RAISES: Exception if any key is not valid for the specified operation types.
 *
 * USAGE: Called by block search endpoints when key-based filtering is requested.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.validate_path_filter_keys(
    _operation_types INT[],
    _set_of_keys     JSON
)
RETURNS VOID
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
DECLARE
  __is_key_incorrect BOOLEAN := FALSE;
  __invalid_key      TEXT    := NULL;
BEGIN
  -- Check if provided keys are correct
  WITH user_provided_keys AS (
    SELECT json_array_elements_text(_set_of_keys) AS given_key
  ),
  haf_keys AS (
    SELECT json_array_elements_text(
      hafah_endpoints.get_operation_keys((SELECT unnest(_operation_types)))
    ) AS keys
  ),
  check_if_given_keys_are_correct AS (
    SELECT
      up.given_key,
      hk.keys IS NULL AS incorrect_key
    FROM user_provided_keys up
    LEFT JOIN haf_keys hk
      ON REPLACE(REPLACE(hk.keys, ' ', ''), '\', '')
       = REPLACE(REPLACE(up.given_key, ' ', ''), '\', '')
  )
  SELECT given_key, incorrect_key
  INTO __invalid_key, __is_key_incorrect
  FROM check_if_given_keys_are_correct
  WHERE incorrect_key
  LIMIT 1;

  IF __is_key_incorrect THEN
    RAISE EXCEPTION 'Invalid key %', __invalid_key;
  END IF;
END
$$;

/*
 * validate_single_operation_type: Validates that exactly one operation type
 * is specified.
 *
 * PARAMETERS:
 *   _operation_types - Array of operation type IDs
 *
 * RAISES: Exception if array length != 1 or array is NULL.
 *
 * USAGE: Called by endpoints that require exactly one operation type filter.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.validate_single_operation_type(_operation_types INT[])
RETURNS VOID
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
BEGIN
  IF array_length(_operation_types, 1) != 1 OR _operation_types IS NULL THEN
    RAISE EXCEPTION 'Invalid set of operations, use single operation. ';
  END IF;
END
$$;

RESET ROLE;
