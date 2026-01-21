-- =============================================================================
-- Authority Helper Functions
-- =============================================================================
-- Functions for retrieving account authority information including keys,
-- account auths, and weight thresholds for different key types.
-- =============================================================================

SET ROLE hafbe_owner;

-- -----------------------------------------------------------------------------
-- Helper Functions
-- -----------------------------------------------------------------------------

/*
 * create_authority_object: Creates a JSON array representing an authority entry.
 *
 * Hive authority format uses [weight, key_or_account] pairs where weight
 * indicates the voting power of that key/account in multi-sig operations.
 *
 * PARAMETERS:
 *   _key    - Public key string or account name
 *   _weight - Authority weight (contribution to threshold)
 *
 * RETURNS: JSON array in format [weight, "key_or_account"]
 *
 * EXAMPLE:
 *   create_authority_object('STM6...', 1) -> [1, "STM6..."]
 */
CREATE OR REPLACE FUNCTION hafbe_backend.create_authority_object(
    _key    TEXT,
    _weight INT
)
RETURNS JSON
LANGUAGE 'plpgsql' IMMUTABLE
AS
$$
BEGIN
  -- Format: [weight, "key"] - matches Hive authority JSON structure
  RETURN ('[' || _weight || ',' || '"' || _key || '"' || ']')::JSON;
END
$$;

-- -----------------------------------------------------------------------------
-- Main Authority Functions
-- -----------------------------------------------------------------------------

/*
 * get_account_authority: Retrieves complete authority information for a key type.
 *
 * Returns key auths (public keys), account auths (other accounts that can sign),
 * and the weight threshold required for valid signatures.
 *
 * PARAMETERS:
 *   _account_id - Account ID to retrieve authority for
 *   _key_kind   - Key type: 'OWNER', 'ACTIVE', or 'POSTING'
 *
 * RETURNS: authority_type with key_auths, account_auths, and weight_threshold
 *
 * NOTE: MEMO and WITNESS_SIGNING keys are excluded as they don't use
 * multi-sig authority structures.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.get_account_authority(
    _account_id INT,
    _key_kind   hafd.key_type
)
RETURNS hafbe_backend.authority_type
LANGUAGE 'plpgsql' STABLE
SET JIT = OFF
SET join_collapse_limit = 16
SET from_collapse_limit = 16
AS
$$
DECLARE
  __result hafbe_backend.authority_type;
BEGIN
  RETURN (
    /*
     * =========================================================================
     * CTE: get_key_auth
     * =========================================================================
     * PURPOSE: Fetch all public keys authorized for this key type.
     *
     * Joins keyauth_a (account-key associations) with keyauth_k (key data)
     * to get the actual public key strings with their weights.
     */
    WITH get_key_auth AS (
      SELECT
        hafbe_backend.create_authority_object(
          hive.public_key_to_string(keys.key),
          active_key_auths.w
        ) AS key_auth
      FROM hafd.hafbe_app_keyauth_a active_key_auths
      JOIN hafd.hafbe_app_keyauth_k keys ON active_key_auths.key_serial_id = keys.key_id
      WHERE
        active_key_auths.account_id = _account_id AND
        active_key_auths.key_kind = _key_kind AND
        -- Exclude single-key types that don't participate in multi-sig
        active_key_auths.key_kind NOT IN ('MEMO', 'WITNESS_SIGNING')
      ORDER BY hive.public_key_to_string(keys.key)
    ),

    /*
     * =========================================================================
     * CTE: get_account_auth
     * =========================================================================
     * PURPOSE: Fetch all account-based authorities for this key type.
     *
     * Account auths allow other accounts to sign on behalf of this account,
     * useful for hierarchical permission structures.
     */
    get_account_auth AS (
      SELECT
        hafbe_backend.create_authority_object(
          av.name,
          active_account_auths.w
        ) AS key_auth
      FROM hafd.hafbe_app_accountauth_a active_account_auths
      JOIN hive.accounts_view av ON active_account_auths.account_auth_id = av.id
      WHERE
        active_account_auths.account_id = _account_id AND
        active_account_auths.key_kind = _key_kind
      ORDER BY av.name
    ),

    /*
     * =========================================================================
     * CTE: get_weight_threshold
     * =========================================================================
     * PURPOSE: Get the minimum combined weight required for valid signatures.
     *
     * For a transaction to be valid, the sum of weights from provided
     * signatures must meet or exceed this threshold.
     */
    get_weight_threshold AS (
      SELECT wt.weight_threshold
      FROM hafd.hafbe_app_authority_definition wt
      WHERE
        wt.account_id = _account_id AND
        wt.key_kind = _key_kind
    )

    SELECT ROW(
      -- key_auths: Array of [weight, "pubkey"] pairs
      COALESCE(
        (SELECT json_agg(gka.key_auth) FROM get_key_auth gka),
        '[]'
      )::JSON,

      -- account_auths: Array of [weight, "account"] pairs
      COALESCE(
        (SELECT json_agg(gaa.key_auth) FROM get_account_auth gaa),
        '[]'
      )::JSON,

      -- weight_threshold: Minimum weight needed (defaults to 1)
      COALESCE(
        (SELECT wt.weight_threshold FROM get_weight_threshold wt),
        1
      )
    )
  );
END
$$;

-- -----------------------------------------------------------------------------
-- Single Key Retrieval Functions
-- -----------------------------------------------------------------------------

/*
 * get_account_memo: Retrieves the memo public key for an account.
 *
 * The memo key is used for encrypting/decrypting private messages in transfers.
 * Unlike authority keys, memo is a single key without multi-sig support.
 *
 * PARAMETERS:
 *   _account_id - Account ID to retrieve memo key for
 *
 * RETURNS: Public key string or empty string if not set
 */
CREATE OR REPLACE FUNCTION hafbe_backend.get_account_memo(
    _account_id INT
)
RETURNS TEXT
LANGUAGE 'plpgsql' STABLE
SET JIT = OFF
SET join_collapse_limit = 16
SET from_collapse_limit = 16
AS
$$
BEGIN
  RETURN COALESCE(
    (
      SELECT hive.public_key_to_string(keys.key)
      FROM hafd.hafbe_app_keyauth_a active_key_auths
      JOIN hafd.hafbe_app_keyauth_k keys ON active_key_auths.key_serial_id = keys.key_id
      WHERE
        active_key_auths.account_id = _account_id AND
        active_key_auths.key_kind = 'MEMO'
    ),
    ''
  );
END
$$;

/*
 * get_account_witness_signing: Retrieves the witness signing key for an account.
 *
 * The witness signing key is used by witness nodes to sign blocks.
 * Only relevant for accounts that are registered as witnesses.
 *
 * PARAMETERS:
 *   _account_id - Account ID to retrieve witness signing key for
 *
 * RETURNS: Public key string or empty string if not set/not a witness
 */
CREATE OR REPLACE FUNCTION hafbe_backend.get_account_witness_signing(
    _account_id INT
)
RETURNS TEXT
LANGUAGE 'plpgsql' STABLE
SET JIT = OFF
SET join_collapse_limit = 16
SET from_collapse_limit = 16
AS
$$
BEGIN
  RETURN COALESCE(
    (
      SELECT hive.public_key_to_string(keys.key)
      FROM hafd.hafbe_app_keyauth_a active_key_auths
      JOIN hafd.hafbe_app_keyauth_k keys ON active_key_auths.key_serial_id = keys.key_id
      WHERE
        active_key_auths.account_id = _account_id AND
        active_key_auths.key_kind = 'WITNESS_SIGNING'
    ),
    ''
  );
END
$$;

RESET ROLE;
