SET ROLE hafbe_owner;

/*
 * process_account_stats: Processes account parameters from blockchain operations.
 *
 * Core operations: Extracts account creation info (mined, recovery_account, created),
 * recovery events, voting rights changes, and account token claims. Updates the
 * hafbe_app.account_parameters table with latest values.
 */
CREATE OR REPLACE FUNCTION hafbe_app.process_account_stats(_from INT, _to INT)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
AS
$$
DECLARE
  -- Hardfork 11 block - recovery account logic changed after this (pre-HF11 defaults to 'steem')
  _hf11_block                        INT := (SELECT block_num FROM hafd.applied_hardforks WHERE hardfork_num = 11);
  -- Cache operation type IDs for performance (avoid repeated function calls)
  _op_pow                            INT := hafbe_backend.op_pow();
  _op_pow2                           INT := hafbe_backend.op_pow2();
  _op_account_created                INT := hafbe_backend.op_account_created();
  _op_account_create                 INT := hafbe_backend.op_account_create();
  _op_create_claimed_account         INT := hafbe_backend.op_create_claimed_account();
  _op_account_create_with_delegation INT := hafbe_backend.op_account_create_with_delegation();
  _op_changed_recovery_account       INT := hafbe_backend.op_changed_recovery_account();
  _op_recover_account                INT := hafbe_backend.op_recover_account();
  _op_decline_voting_rights          INT := hafbe_backend.op_decline_voting_rights();
  _op_claim_account                  INT := hafbe_backend.op_claim_account();
BEGIN

  /*
   * ===================================================================================
   * SECTION 1: Account Creation Parameters (mined, recovery_account, created)
   * ===================================================================================
   * This section processes operations that establish or modify account creation metadata:
   *   - pow/pow2: Account was mined (mined=TRUE)
   *   - account_create/create_claimed_account/account_create_with_delegation: Account was
   *     created by another account (mined=FALSE)
   *   - account_created: Virtual op with authoritative timestamp and recovery_account
   *   - changed_recovery_account: User changing their recovery account
   */

  /*
   * ===================================================================================
   * CTE: parsed_operations
   * ===================================================================================
   * WHY MATERIALIZED: This CTE performs expensive JSON parsing via CROSS JOIN LATERAL
   * with helper functions. Materializing ensures each operation is parsed exactly once,
   * preventing repeated evaluation during subsequent JOINs.
   *
   * DATA FLOW:
   *   1. Filter operations_view_extended to relevant op types in block range
   *   2. For each operation, call appropriate parse_* function based on op_type_id
   *   3. Extract: account_name, mined, recovery_account, created
   *
   * CROSS JOIN LATERAL PATTERN:
   *   The CASE expression returns a composite type (impacted_account_parameters).
   *   The .* syntax expands this into individual columns. This is equivalent to
   *   calling multiple functions but with a single CASE for routing.
   *
   * EXAMPLE:
   *   pow_operation for account "alice" at block 1000:
   *   | account_name | mined | recovery_account | created             |
   *   |--------------|-------|------------------|---------------------|
   *   | alice        | TRUE  | NULL             | 2016-03-24 12:00:00 |
   *
   *   changed_recovery_account for "bob" changing to "charlie":
   *   | account_name | mined | recovery_account | created |
   *   |--------------|-------|------------------|---------|
   *   | bob          | NULL  | charlie          | NULL    |
   */
  WITH parsed_operations AS MATERIALIZED (
    SELECT
      iap.account_name,
      iap.mined,
      iap.recovery_account,
      iap.created,
      ho.op_type_id,
      ho.id AS source_op
    FROM hafbe_app.operations_view_extended ho
    CROSS JOIN LATERAL (
      SELECT (
        CASE
          WHEN ho.op_type_id = _op_pow THEN
            hafbe_backend.parse_pow_operation(ho.body_value, ho.timestamp)
          WHEN ho.op_type_id = _op_pow2 THEN
            hafbe_backend.parse_pow2_operation(ho.body_value, ho.timestamp)
          WHEN ho.op_type_id = _op_account_created THEN
            hafbe_backend.parse_account_created_operation(ho.body_value, ho.timestamp, ho.block_num > _hf11_block)
          WHEN ho.op_type_id IN (_op_account_create, _op_create_claimed_account, _op_account_create_with_delegation) THEN
            hafbe_backend.parse_account_create_operation(ho.body_value, ho.timestamp)
          WHEN ho.op_type_id = _op_changed_recovery_account THEN
            hafbe_backend.parse_changed_recovery_account_operation(ho.body_value)
        END
      ).*
    ) AS iap
    WHERE ho.op_type_id IN (
      _op_pow, _op_pow2, _op_account_created, _op_account_create,
      _op_create_claimed_account, _op_account_create_with_delegation, _op_changed_recovery_account
    )
    AND ho.block_num BETWEEN _from AND _to
  ),

  /*
   * ===================================================================================
   * CTE: final_values
   * ===================================================================================
   * PURPOSE: For each account, determine the final value of each field when multiple
   *          operations affect the same account in this block range.
   *
   * THE CHALLENGE:
   *   An account may have multiple operations in one block range. Example:
   *   - account_create_operation (mined=FALSE)
   *   - account_created_operation (recovery_account='creator', created=timestamp)
   *   - changed_recovery_account_operation (recovery_account='new_recovery')
   *
   *   We need: mined from first op, recovery_account from last op, created from
   *   the authoritative virtual op (account_created).
   *
   * WINDOW FUNCTION PATTERN - "First/Last Non-NULL":
   *
   *   FIRST_VALUE(field) OVER (
   *     PARTITION BY account_name
   *     ORDER BY CASE WHEN field IS NOT NULL THEN 0 ELSE 1 END, source_op [ASC|DESC]
   *   )
   *
   *   The ORDER BY has two parts:
   *   1. CASE puts non-NULL values first (0) and NULLs last (1)
   *   2. source_op determines which non-NULL to pick (ASC=first, DESC=last)
   *
   * FIELD-SPECIFIC LOGIC:
   *   - mined: First non-NULL (only set once at account creation, never changes)
   *   - recovery_account: Last non-NULL (most recent change wins)
   *   - created: Prefer account_created_operation (priority 0) over other ops (priority 1)
   *              because the virtual op has the authoritative timestamp
   *
   * LATE BINDING: Keep account_name here; resolve account_id in final INSERT.
   *
   * EXAMPLE:
   *   Account "alice" has 3 operations:
   *   | source_op | mined | recovery_account | created    | op_type_id |
   *   |-----------|-------|------------------|------------|------------|
   *   | 1001      | FALSE | NULL             | 2024-01-15 | 9 (create) |
   *   | 1002      | NULL  | bob              | 2024-01-15 | 80 (virt)  |
   *   | 1003      | NULL  | charlie          | NULL       | 26 (change)|
   *
   *   Result:
   *   - mined = FALSE (first non-NULL from op 1001)
   *   - recovery_account = charlie (last non-NULL from op 1003)
   *   - created = 2024-01-15 from op 1002 (account_created has priority)
   */
  final_values AS MATERIALIZED (
    SELECT DISTINCT ON (account_name)
      po.account_name,
      FIRST_VALUE(po.mined) OVER (
        PARTITION BY po.account_name
        ORDER BY CASE WHEN po.mined IS NOT NULL THEN 0 ELSE 1 END, po.source_op
      ) AS mined,
      FIRST_VALUE(po.recovery_account) OVER (
        PARTITION BY po.account_name
        ORDER BY CASE WHEN po.recovery_account IS NOT NULL THEN 0 ELSE 1 END, po.source_op DESC
      ) AS recovery_account,
      FIRST_VALUE(po.created) OVER (
        PARTITION BY po.account_name
        ORDER BY
          CASE WHEN po.op_type_id = _op_account_created AND po.created IS NOT NULL THEN 0
               WHEN po.created IS NOT NULL THEN 1
               ELSE 2
          END,
          po.source_op
      ) AS created
    FROM parsed_operations po
    ORDER BY account_name
  )

  /*
   * UPSERT with field-specific COALESCE patterns:
   *
   * IMMUTABLE FIELDS (mined, created):
   *   COALESCE(ap.field, EXCLUDED.field, DEFAULT)
   *   - Existing value takes precedence (set once at account creation, never changes)
   *   - Prevents subsequent operations from overwriting original values
   *   - Example: pow operations after account creation won't overwrite mined/created
   *
   * MUTABLE FIELDS (recovery_account):
   *   COALESCE(EXCLUDED.field, ap.field, DEFAULT)
   *   - New value takes precedence (updates should take effect)
   *   - If new value is NULL, existing value is preserved
   *
   * LATE BINDING: Resolve account_id via subquery on already-reduced data
   * (one row per account after DISTINCT ON).
   */
  INSERT INTO hafbe_app.account_parameters AS ap (account, mined, recovery_account, created)
  SELECT
    (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = fv.account_name) AS account_id,
    fv.mined,
    fv.recovery_account,
    fv.created
  FROM final_values fv
  ON CONFLICT ON CONSTRAINT pk_account_parameters
  DO UPDATE SET
    mined            = COALESCE(ap.mined, EXCLUDED.mined, hafbe_backend.default_mined()),
    recovery_account = COALESCE(EXCLUDED.recovery_account, ap.recovery_account, hafbe_backend.default_recovery_account()),
    created          = COALESCE(ap.created, EXCLUDED.created, hafbe_backend.default_timestamp());


  /*
   * ===================================================================================
   * SECTION 2: Account Recovery Tracking (last_account_recovery)
   * ===================================================================================
   * Tracks when accounts were recovered via recover_account_operation.
   * Only the most recent recovery timestamp is stored.
   */

  /*
   * ===================================================================================
   * CTE: recovery_operations
   * ===================================================================================
   * WHY MATERIALIZED: JSON extraction is expensive; materializing ensures single parse.
   *
   * NOTE: Using operations_view_extended because timestamp IS needed.
   *
   * PURPOSE: Extract recovery events with timestamp using helper function.
   *          Keep account_name for late binding.
   */
  WITH recovery_operations AS MATERIALIZED (
    SELECT
      parsed.account_name,
      parsed.recovery_timestamp,
      ov.id AS source_op
    FROM hafbe_app.operations_view_extended ov
    CROSS JOIN hafbe_backend.parse_recover_account_operation(ov.body_value, ov.timestamp) parsed
    WHERE ov.op_type_id = _op_recover_account
      AND ov.block_num BETWEEN _from AND _to
  ),

  /*
   * ===================================================================================
   * CTE: recovery_final
   * ===================================================================================
   * PURPOSE: If an account was recovered multiple times in this range, keep only
   *          the most recent recovery event.
   *
   * "LAST OPERATION WINS" PATTERN:
   *   ROW_NUMBER() OVER (PARTITION BY account_name ORDER BY source_op DESC)
   *
   *   By ordering DESC, rn=1 identifies the MOST RECENT operation.
   *   WHERE rn = 1 in the INSERT filters to only the latest recovery.
   *
   * LATE BINDING: Resolve account_id via subquery on reduced dataset.
   */
  recovery_final AS (
    SELECT
      ro.account_name,
      ro.recovery_timestamp,
      ROW_NUMBER() OVER (PARTITION BY ro.account_name ORDER BY ro.source_op DESC) AS rn
    FROM recovery_operations ro
  )
  INSERT INTO hafbe_app.account_parameters AS ap (account, last_account_recovery)
  SELECT
    (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = rf.account_name) AS account_id,
    rf.recovery_timestamp
  FROM recovery_final rf
  WHERE rf.rn = 1
  ON CONFLICT ON CONSTRAINT pk_account_parameters
  DO UPDATE SET
    last_account_recovery = EXCLUDED.last_account_recovery;


  /*
   * ===================================================================================
   * SECTION 3: Voting Rights (can_vote)
   * ===================================================================================
   * Tracks decline_voting_rights_operation. The 'decline' field in JSON:
   *   - TRUE: User wants to LOSE voting rights (can_vote becomes FALSE)
   *   - FALSE: User wants to REGAIN voting rights (can_vote becomes TRUE)
   */

  /*
   * ===================================================================================
   * CTE: voting_operations
   * ===================================================================================
   * WHY MATERIALIZED: JSON extraction is expensive; materializing ensures single parse.
   *
   * NOTE: Using operations_view (not _extended) since timestamp is not needed.
   *
   * PURPOSE: Parse voting rights operations using helper function.
   *          The parser inverts 'decline' to get can_vote.
   *          Keep account_name for late binding (resolve ID on smallest CTE).
   */
  WITH voting_operations AS MATERIALIZED (
    SELECT
      parsed.account_name,
      parsed.can_vote,
      ov.id AS source_op
    FROM hafbe_app.operations_view ov
    CROSS JOIN hafbe_backend.parse_decline_voting_rights_operation(ov.body_value) parsed
    WHERE ov.op_type_id = _op_decline_voting_rights
      AND ov.block_num BETWEEN _from AND _to
  ),

  /*
   * ===================================================================================
   * CTE: voting_rights_final
   * ===================================================================================
   * PURPOSE: If multiple voting rights changes in this range, keep only the most recent.
   *          Same "last operation wins" pattern as recovery_operations.
   *
   * LATE BINDING: Resolve account_id here on reduced dataset (one row per account).
   */
  voting_rights_final AS (
    SELECT
      vo.account_name,
      vo.can_vote,
      ROW_NUMBER() OVER (PARTITION BY vo.account_name ORDER BY vo.source_op DESC) AS rn
    FROM voting_operations vo
  )
  INSERT INTO hafbe_app.account_parameters AS ap (account, can_vote)
  SELECT
    (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = vrf.account_name) AS account_id,
    vrf.can_vote
  FROM voting_rights_final vrf
  WHERE vrf.rn = 1
  ON CONFLICT ON CONSTRAINT pk_account_parameters
  DO UPDATE SET
    can_vote = EXCLUDED.can_vote;


  /*
   * ===================================================================================
   * SECTION 4: Account Token Tracking (pending_claimed_accounts)
   * ===================================================================================
   * Tracks account creation tokens:
   *   - claim_account: Creator gains +1 token
   *   - create_claimed_account: Creator spends -1 token
   *
   * Unlike other fields, this is a COUNTER that accumulates over time.
   */

  /*
   * ===================================================================================
   * CTE: claimed_operations
   * ===================================================================================
   * WHY MATERIALIZED: The SUM aggregation groups multiple operations per account.
   *
   * NOTE: Using operations_view (not _extended) since timestamp is not needed.
   *
   * PURPOSE: Parse claim operations using helper function and aggregate token deltas.
   *
   * TOKEN DELTA CALCULATION:
   *   CASE WHEN op_type_id = _op_claim_account THEN 1 ELSE -1 END
   *
   *   claim_account: +1 (gaining a token)
   *   create_claimed_account: -1 (spending a token)
   *
   * GROUP BY aggregates all token changes for each account in this block range.
   * LATE BINDING: Group by account_name first, then resolve ID on aggregated result.
   *
   * EXAMPLE:
   *   Account "alice" in this range:
   *   - claim_account: +1
   *   - claim_account: +1
   *   - create_claimed_account: -1
   *   Result: token_delta = +1
   */
  WITH claimed_operations AS MATERIALIZED (
    SELECT
      parsed.account_name,
      SUM(CASE WHEN ov.op_type_id = _op_claim_account THEN 1 ELSE -1 END) AS token_delta
    FROM hafbe_app.operations_view ov
    CROSS JOIN hafbe_backend.parse_claim_account_operation(ov.body_value) parsed
    WHERE ov.op_type_id IN (_op_claim_account, _op_create_claimed_account)
      AND ov.block_num BETWEEN _from AND _to
    GROUP BY parsed.account_name
  )

  /*
   * ADDITIVE UPSERT PATTERN:
   *   DO UPDATE SET pending_claimed_accounts = ap.pending_claimed_accounts + EXCLUDED.pending_claimed_accounts
   *
   * Unlike other fields where we REPLACE the value, here we ADD to it.
   * The delta from this batch is added to the existing count.
   *
   * LATE BINDING: Resolve account_id via subquery on already-aggregated data.
   */
  INSERT INTO hafbe_app.account_parameters AS ap (account, pending_claimed_accounts)
  SELECT
    (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = co.account_name) AS account_id,
    co.token_delta
  FROM claimed_operations co
  ON CONFLICT ON CONSTRAINT pk_account_parameters
  DO UPDATE SET
    pending_claimed_accounts = ap.pending_claimed_accounts + EXCLUDED.pending_claimed_accounts;

END
$$;

RESET ROLE;
