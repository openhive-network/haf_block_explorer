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
LANGUAGE 'plpgsql'
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

RESET ROLE;
