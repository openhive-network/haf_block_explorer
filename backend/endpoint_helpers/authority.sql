-- =============================================================================
-- Authority Helper Functions
-- =============================================================================
-- Functions for retrieving account authority information including keys,
-- account auths, and weight thresholds for different key types.
--
-- Owner/active/posting authorities and the memo key come from l2_framework's
-- block-versioned tables (l2.authority_threshold, l2.authority_key,
-- l2.authority_account), read as of haf_block_explorer's own head block so they
-- agree with the rest of the explorer's data. l2_framework syncs independently:
-- when it is behind that block its latest rows are the ones effective, so the
-- same predicate serves both cases. l2_framework does not track witness signing
-- keys; those come from hafbe_app.current_witnesses.
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
LANGUAGE plpgsql IMMUTABLE
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
 * multi-sig authority structures (l2_framework tracks no WITNESS_SIGNING role,
 * so asking for it fails the role cast).
 */
CREATE OR REPLACE FUNCTION hafbe_backend.get_account_authority(
    _account_id INT,
    _key_kind   hafd.key_type
)
RETURNS hafbe_backend.authority_type
LANGUAGE plpgsql STABLE
SET JIT = OFF
SET join_collapse_limit = 16
SET from_collapse_limit = 16
AS
$$
DECLARE
  __role  l2.authority_role := lower(_key_kind::TEXT)::l2.authority_role;
  __block INT := hafbe_backend.get_hafbe_head_block();
BEGIN
  RETURN (
    /*
     * =========================================================================
     * CTE: get_key_auth
     * =========================================================================
     * PURPOSE: Fetch all public keys authorized for this key type.
     */
    WITH get_key_auth AS (
      SELECT
        hafbe_backend.create_authority_object(
          hive.public_key_to_string(ak.public_key),
          ak.weight
        ) AS key_auth
      FROM l2.authority_key ak
      WHERE
        ak.account_id = _account_id AND
        ak.role = __role AND
        -- Exclude the memo key: it doesn't participate in multi-sig
        ak.role <> 'memo' AND
        ak.valid_from <= __block AND
        (ak.valid_to IS NULL OR ak.valid_to > __block)
      ORDER BY hive.public_key_to_string(ak.public_key)
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
          aa.weight
        ) AS key_auth
      FROM l2.authority_account aa
      JOIN hive.accounts_view av ON aa.ref_account_id = av.id
      WHERE
        aa.account_id = _account_id AND
        aa.role = __role AND
        aa.valid_from <= __block AND
        (aa.valid_to IS NULL OR aa.valid_to > __block)
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
      FROM l2.authority_threshold wt
      WHERE
        wt.account_id = _account_id AND
        wt.role = __role AND
        wt.valid_from <= __block AND
        (wt.valid_to IS NULL OR wt.valid_to > __block)
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
LANGUAGE plpgsql STABLE
SET JIT = OFF
SET join_collapse_limit = 16
SET from_collapse_limit = 16
AS
$$
DECLARE
  __block INT := hafbe_backend.get_hafbe_head_block();
BEGIN
  RETURN COALESCE(
    (
      SELECT hive.public_key_to_string(ak.public_key)
      FROM l2.authority_key ak
      WHERE
        ak.account_id = _account_id AND
        ak.role = 'memo' AND
        ak.valid_from <= __block AND
        (ak.valid_to IS NULL OR ak.valid_to > __block)
    ),
    ''
  );
END
$$;

/*
 * get_account_witness_signing: Retrieves the witness signing key for an account.
 *
 * The witness signing key is used by witness nodes to sign blocks.
 * Only relevant for accounts that are registered as witnesses. Read from
 * hafbe_app.current_witnesses, which process_witness_stats() keeps at the
 * latest key set by witness_update / witness_set_properties (or the creating
 * pow/pow2 op).
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
LANGUAGE plpgsql STABLE
SET JIT = OFF
SET join_collapse_limit = 16
SET from_collapse_limit = 16
AS
$$
BEGIN
  RETURN COALESCE(
    (
      SELECT cw.signing_key
      FROM hafbe_app.current_witnesses cw
      WHERE cw.witness_id = _account_id
    ),
    ''
  );
END
$$;

RESET ROLE;
