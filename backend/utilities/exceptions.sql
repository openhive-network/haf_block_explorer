SET ROLE hafbe_owner;

-- ============================================================================
-- Exception Functions
-- ============================================================================
-- Functions that raise user-friendly exceptions for API error responses.
-- These are called by validation functions or directly when an error condition
-- is detected. Each function raises a specific, descriptive EXCEPTION message.
--
-- NOTE: Validation logic belongs in validators.sql. This file contains only
-- the exception-raising functions that format error messages for the API.
-- ============================================================================

-- ============================================================================
-- Account/Entity Not Found Exceptions
-- ============================================================================

/*
 * rest_raise_missing_account: Raises an exception when the requested account
 * does not exist in the database.
 *
 * PARAMETERS:
 *   _account_name - The account name that was not found
 *
 * USAGE: Called by hafah_backend.get_account() and similar functions when
 *        the account lookup returns NULL.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.rest_raise_missing_account(_account_name TEXT)
RETURNS VOID
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
BEGIN
  RAISE EXCEPTION 'Account ''%'' does not exist', _account_name;
END
$$;

/*
 * rest_raise_missing_witness: Raises an exception when the requested witness
 * does not exist in the current_witnesses table.
 *
 * PARAMETERS:
 *   _account_name - The witness name that was not found
 *
 * USAGE: Called by hafbe_backend.validate_witness() when the witness ID is
 *        not found in hafbe_app.current_witnesses.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.rest_raise_missing_witness(_account_name TEXT)
RETURNS VOID
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
BEGIN
  RAISE EXCEPTION 'Witness ''%'' does not exist', _account_name;
END
$$;

-- ============================================================================
-- Block/Transaction Exceptions
-- ============================================================================

/*
 * raise_block_num_too_high_exception: Raises an exception when the requested
 * block number exceeds the current head block.
 *
 * PARAMETERS:
 *   _block_num      - The requested block number (NUMERIC for large values)
 *   _head_block_num - The current head block number
 *
 * USAGE: Called by hafbe_backend.validate_block_num_too_high() when the user
 *        requests a block that hasn't been processed yet.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.raise_block_num_too_high_exception(
    _block_num      NUMERIC,
    _head_block_num INT
)
RETURNS VOID
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
BEGIN
  RAISE EXCEPTION 'Block_num ''%'' is higher than head block (%).', _block_num, _head_block_num;
END
$$;

/*
 * raise_unknown_hash_exception: Raises an exception when the provided hash
 * (block hash or transaction hash) is not found in the database.
 *
 * PARAMETERS:
 *   _hash - The hash string that was not found
 *
 * USAGE: Called when looking up a block or transaction by hash fails.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.raise_unknown_hash_exception(_hash TEXT)
RETURNS VOID
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
BEGIN
  RAISE EXCEPTION 'Block or transaction hash ''%'' does not exist in database.', _hash;
END
$$;

RESET ROLE;
