SET ROLE hafbe_owner;

/*
 * Account Operation Parsers
 *
 * Helper type and functions for parsing account-related operations.
 * Used by hafbe_app.process_account_stats() to extract account parameters
 * from operation JSON bodies.
 */

DROP TYPE IF EXISTS hafbe_backend.impacted_account_parameters CASCADE;
CREATE TYPE hafbe_backend.impacted_account_parameters AS (
  account_name     TEXT,      -- account affected by the operation
  mined            BOOLEAN,   -- TRUE if mined (pow/pow2), FALSE if created, NULL if unchanged
  recovery_account TEXT,      -- who can recover this account, NULL if unchanged
  created          TIMESTAMP  -- when account was created, NULL if unchanged
);


/*
 * ===================================================================================
 * parse_pow_operation
 * ===================================================================================
 * PURPOSE: Parse pow_operation (original proof-of-work mining from early blockchain).
 *
 * JSON STRUCTURE (body_value, no type wrapper):
 *   { "worker_account": "account-name" }
 *
 * RETURNS:
 *   - account_name: The miner's account
 *   - mined: TRUE (pow accounts are always mined)
 *   - recovery_account: NULL (not set by this operation)
 *   - created: Operation timestamp
 */
CREATE OR REPLACE FUNCTION hafbe_backend.parse_pow_operation(
    _body      JSONB,
    _timestamp TIMESTAMP
)
RETURNS hafbe_backend.impacted_account_parameters
LANGUAGE 'plpgsql' STABLE
AS $$
DECLARE
  __result hafbe_backend.impacted_account_parameters;
BEGIN
  __result := (
    _body ->> 'worker_account',
    TRUE,
    NULL,
    _timestamp
  );

  RETURN __result;
END
$$;


/*
 * ===================================================================================
 * parse_pow2_operation
 * ===================================================================================
 * PURPOSE: Parse pow2_operation (updated proof-of-work mining with nested structure).
 *
 * JSON STRUCTURE (body_value, no type wrapper):
 *   { "work": { "value": { "input": { "worker_account": "account-name" } } } }
 *
 * NOTE: Deeper nesting than pow_operation due to protocol changes.
 *
 * RETURNS:
 *   - account_name: The miner's account (deeply nested)
 *   - mined: TRUE (pow2 accounts are always mined)
 *   - recovery_account: NULL (not set by this operation)
 *   - created: Operation timestamp
 */
CREATE OR REPLACE FUNCTION hafbe_backend.parse_pow2_operation(
    _body      JSONB,
    _timestamp TIMESTAMP
)
RETURNS hafbe_backend.impacted_account_parameters
LANGUAGE 'plpgsql' STABLE
AS $$
DECLARE
  __result hafbe_backend.impacted_account_parameters;
BEGIN
  __result := (
    _body -> 'work' -> 'value' -> 'input' ->> 'worker_account',
    TRUE,
    NULL,
    _timestamp
  );

  RETURN __result;
END
$$;


/*
 * ===================================================================================
 * parse_account_created_operation
 * ===================================================================================
 * PURPOSE: Parse account_created_operation (virtual op emitted when account is created).
 *          This is the authoritative source for creation timestamp and recovery account.
 *
 * JSON STRUCTURE (body_value, no type wrapper):
 *   { "new_account_name": "...", "creator": "..." }
 *
 * HARDFORK LOGIC (recovery_account):
 *   - Pre-HF11: Always defaults to pre_hf11_recovery_account() ('steem')
 *   - Post-HF11:
 *       - If creator = new_account_name (self-created): default_recovery_account() ('')
 *       - If creator = temp_creator_account() ('temp'): default_recovery_account() ('')
 *       - Otherwise: recovery_account = creator
 *
 * RETURNS:
 *   - account_name: The newly created account
 *   - mined: NULL (determined by triggering operation, not this virtual op)
 *   - recovery_account: Computed based on hardfork rules
 *   - created: Authoritative creation timestamp
 */
CREATE OR REPLACE FUNCTION hafbe_backend.parse_account_created_operation(
    _body      JSONB,
    _timestamp TIMESTAMP,
    _is_hf11   BOOLEAN
)
RETURNS hafbe_backend.impacted_account_parameters
LANGUAGE 'plpgsql' STABLE
AS $$
DECLARE
  _new_account TEXT := _body ->> 'new_account_name';
  _creator     TEXT := _body ->> 'creator';
  _recovery    TEXT;
  __result     hafbe_backend.impacted_account_parameters;
BEGIN
  -- Determine recovery account based on hardfork rules
  IF _is_hf11 AND (_creator = _new_account OR _creator = hafbe_backend.temp_creator_account()) THEN
    _recovery := hafbe_backend.default_recovery_account();
  ELSIF NOT _is_hf11 THEN
    _recovery := hafbe_backend.pre_hf11_recovery_account();
  ELSE
    _recovery := _creator;
  END IF;

  __result := (
    _new_account,
    NULL,
    _recovery,
    _timestamp
  );

  RETURN __result;
END
$$;


/*
 * ===================================================================================
 * parse_account_create_operation
 * ===================================================================================
 * PURPOSE: Parse account creation operations where another account pays the fee.
 *          Handles: account_create, create_claimed_account, account_create_with_delegation
 *
 * JSON STRUCTURE (body_value, no type wrapper):
 *   { "new_account_name": "..." }
 *
 * NOTE: These accounts are NOT mined (mined=FALSE). The recovery_account is set
 *       by the accompanying account_created_operation virtual op, not here.
 *
 * RETURNS:
 *   - account_name: The newly created account
 *   - mined: FALSE (fee-based creation, not proof-of-work)
 *   - recovery_account: NULL (set by account_created_operation)
 *   - created: Operation timestamp
 */
CREATE OR REPLACE FUNCTION hafbe_backend.parse_account_create_operation(
    _body      JSONB,
    _timestamp TIMESTAMP
)
RETURNS hafbe_backend.impacted_account_parameters
LANGUAGE 'plpgsql' STABLE
AS $$
DECLARE
  __result hafbe_backend.impacted_account_parameters;
BEGIN
  __result := (
    _body ->> 'new_account_name',
    FALSE,
    NULL,
    _timestamp
  );

  RETURN __result;
END
$$;


/*
 * ===================================================================================
 * parse_changed_recovery_account_operation
 * ===================================================================================
 * PURPOSE: Parse changed_recovery_account_operation (user changing their recovery account).
 *
 * JSON STRUCTURE (body_value, no type wrapper):
 *   { "account": "...", "new_recovery_account": "..." }
 *
 * NOTE: The change takes effect after a 30-day waiting period on the blockchain.
 *       We record the requested change immediately.
 *
 * RETURNS:
 *   - account_name: The account changing its recovery
 *   - mined: NULL (unchanged by this operation)
 *   - recovery_account: The new recovery account
 *   - created: NULL (unchanged by this operation)
 */
CREATE OR REPLACE FUNCTION hafbe_backend.parse_changed_recovery_account_operation(
    _body JSONB
)
RETURNS hafbe_backend.impacted_account_parameters
LANGUAGE 'plpgsql' STABLE
AS $$
DECLARE
  __result hafbe_backend.impacted_account_parameters;
BEGIN
  __result := (
    _body ->> 'account',
    NULL,
    _body ->> 'new_recovery_account',
    NULL
  );

  RETURN __result;
END
$$;


-- =============================================================================
-- Additional Parser Types and Functions
-- Used by other sections of process_account_stats()
-- =============================================================================

/*
 * recover_account_result - Return type for parse_recover_account_operation
 */
DROP TYPE IF EXISTS hafbe_backend.recover_account_result CASCADE;
CREATE TYPE hafbe_backend.recover_account_result AS (
  account_name       TEXT,      -- account that was recovered
  recovery_timestamp TIMESTAMP  -- when recovery occurred
);


/*
 * ===================================================================================
 * parse_recover_account_operation
 * ===================================================================================
 * PURPOSE: Parse recover_account_operation (account recovery event).
 *
 * JSON STRUCTURE (body_value, no type wrapper):
 *   { "account_to_recover": "account-name" }
 *
 * RETURNS:
 *   - account_name: The account that was recovered
 *   - recovery_timestamp: When the recovery occurred
 */
CREATE OR REPLACE FUNCTION hafbe_backend.parse_recover_account_operation(
    _body      JSONB,
    _timestamp TIMESTAMP
)
RETURNS hafbe_backend.recover_account_result
LANGUAGE 'plpgsql' STABLE
AS $$
DECLARE
  __result hafbe_backend.recover_account_result;
BEGIN
  __result := (
    _body ->> 'account_to_recover',
    _timestamp
  );

  RETURN __result;
END
$$;


/*
 * decline_voting_rights_result - Return type for parse_decline_voting_rights_operation
 */
DROP TYPE IF EXISTS hafbe_backend.decline_voting_rights_result CASCADE;
CREATE TYPE hafbe_backend.decline_voting_rights_result AS (
  account_name TEXT,    -- account changing voting rights
  can_vote     BOOLEAN  -- TRUE if account can vote, FALSE if declined
);


/*
 * ===================================================================================
 * parse_decline_voting_rights_operation
 * ===================================================================================
 * PURPOSE: Parse decline_voting_rights_operation (user declining/regaining voting rights).
 *
 * JSON STRUCTURE (body_value, no type wrapper):
 *   { "account": "account-name", "decline": true/false }
 *
 * NOTE: The 'decline' field is INVERTED to get can_vote:
 *   - decline=TRUE  → can_vote=FALSE (user wants to lose voting rights)
 *   - decline=FALSE → can_vote=TRUE  (user wants to regain voting rights)
 *
 * RETURNS:
 *   - account_name: The account changing its voting rights
 *   - can_vote: Whether the account can vote (inverted from 'decline')
 */
CREATE OR REPLACE FUNCTION hafbe_backend.parse_decline_voting_rights_operation(
    _body JSONB
)
RETURNS hafbe_backend.decline_voting_rights_result
LANGUAGE 'plpgsql' STABLE
AS $$
DECLARE
  __result hafbe_backend.decline_voting_rights_result;
BEGIN
  __result := (
    _body ->> 'account',
    NOT (_body ->> 'decline')::BOOLEAN
  );

  RETURN __result;
END
$$;


/*
 * claim_account_result - Return type for parse_claim_account_operation
 */
DROP TYPE IF EXISTS hafbe_backend.claim_account_result CASCADE;
CREATE TYPE hafbe_backend.claim_account_result AS (
  account_name TEXT  -- creator account claiming/spending tokens
);


/*
 * ===================================================================================
 * parse_claim_account_operation
 * ===================================================================================
 * PURPOSE: Parse claim_account_operation and create_claimed_account_operation.
 *          Both operations have the same JSON structure for the creator field.
 *
 * JSON STRUCTURE (body_value, no type wrapper):
 *   { "creator": "account-name" }
 *
 * USAGE:
 *   - claim_account: Creator gains +1 account creation token
 *   - create_claimed_account: Creator spends -1 account creation token
 *   The delta calculation (+1/-1) is done in the processing function.
 *
 * RETURNS:
 *   - account_name: The creator account (who gains/spends the token)
 */
CREATE OR REPLACE FUNCTION hafbe_backend.parse_claim_account_operation(
    _body JSONB
)
RETURNS hafbe_backend.claim_account_result
LANGUAGE 'plpgsql' STABLE
AS $$
DECLARE
  __result hafbe_backend.claim_account_result;
BEGIN
  __result := ROW(_body ->> 'creator');

  RETURN __result;
END
$$;


RESET ROLE;
