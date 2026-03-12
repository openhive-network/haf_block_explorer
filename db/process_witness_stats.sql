SET ROLE hafbe_owner;

/*
 * process_witness_stats: Updates witness configuration and statistics.
 *
 * Core operations: Extracts witness properties from blockchain operations
 * (witness_update, witness_set_properties, feed_publish, pow, pow2) and
 * updates hafbe_app.current_witnesses table.
 *
 * Properties tracked: url, price_feed, bias, feed_updated_at, block_size,
 * signing_key, version, hbd_interest_rate, account_creation_fee,
 * missed_blocks, last_created_block_num, created.
 */
CREATE OR REPLACE FUNCTION hafbe_app.process_witness_stats(_from INT, _to INT)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
SET enable_bitmapscan = OFF
AS $$
DECLARE
  -- Cache operation type IDs to avoid repeated function calls
  _op_witness_set_properties INT := hafbe_backend.op_witness_set_properties();
  _op_witness_update         INT := hafbe_backend.op_witness_update();
  _op_feed_publish           INT := hafbe_backend.op_feed_publish();
  _op_pow                    INT := hafbe_backend.op_pow();
  _op_pow2                   INT := hafbe_backend.op_pow2();
  _op_producer_missed        INT := hafbe_backend.op_producer_missed();
BEGIN

  /*
   * ===================================================================================
   * SECTION 1: Insert/Update Witness Properties
   * ===================================================================================
   * Parse all witness property operations in ONE scan of witness_prop_op_view.
   * Uses parser functions to extract properties from different operation types.
   * Window functions select the latest non-NULL value for each property.
   *
   * UPSERT PATTERN: INSERT witnesses with their properties, UPDATE on conflict.
   * This avoids scanning operations twice (once for insert, once for update).
   */

  /*
   * ===================================================================================
   * CTE: all_property_ops
   * ===================================================================================
   * WHY MATERIALIZED: Single scan of witness_prop_op_view (calls get_impacted_accounts
   * only ONCE for all operations, not 7+ times like the old code).
   *
   * PURPOSE: Gather all witness property operations with block_num for timestamp lookup.
   *
   * OPERATION TYPES INCLUDED:
   *   - witness_set_properties: Modern witness configuration (all properties)
   *   - witness_update: Legacy witness configuration (url, key, props)
   *   - feed_publish: Price feed updates (base/quote amounts)
   *   - pow: Proof-of-work mining (initial signing key)
   *   - pow2: Updated PoW format (initial signing key)
   *
   * NOTE: producer_missed is handled separately in Section 3 (additive counting).
   */
  WITH all_property_ops AS MATERIALIZED (
    SELECT
      wpov.witness,      -- Witness account name (from get_impacted_accounts)
      wpov.value,        -- Operation JSON body (JSONB)
      wpov.op_type_id,   -- Operation type ID (for CASE routing)
      wpov.operation_id, -- Unique operation ID (for ordering within batch)
      wpov.block_num     -- Block number (for timestamp lookup)
    FROM hafbe_backend.witness_prop_op_view wpov
    /*
     * Filter to witness property operations only.
     * Using IN with cached variables is more efficient than OR conditions.
     */
    WHERE wpov.op_type_id IN (
      _op_witness_set_properties, _op_witness_update,
      _op_feed_publish, _op_pow, _op_pow2
    )
    AND wpov.block_num BETWEEN _from AND _to
  ),

  /*
   * ===================================================================================
   * CTE: parsed_properties
   * ===================================================================================
   * WHY MATERIALIZED: Expensive parser function calls, used by window functions.
   *
   * PURPOSE: Parse all properties using operation-specific parser functions.
   * Parsers compute price_feed and bias directly (no JSON parsing in final UPDATE).
   *
   * DATA FLOW:
   *   1. For each operation, call the appropriate parser function
   *   2. Parser returns witness_properties composite type with pre-computed values
   *   3. Expand composite into individual columns with (.)*
   *
   * SIGNING_KEY PRE-FILTERING:
   *   signing_key requires special handling because different operation types have
   *   different priority rules:
   *   - witness_update/witness_set_properties: explicit key updates (take LATEST)
   *   - pow/pow2: initial key when witness created (take FIRST as fallback)
   *   Pre-filtering here avoids complex nested CASE in window functions.
   */
  parsed_properties AS MATERIALIZED (
    SELECT
      apo.witness,
      apo.operation_id,
      apo.block_num,
      /*
       * Pass through op_type_id for use in latest_properties window functions.
       * This allows us to filter operations by type WITHIN the window (e.g.,
       * "get signing_key only from witness_update operations").
       */
      apo.op_type_id,
      /*
       * CASE expression selects the appropriate parser based on operation type.
       *
       * WHY CASE (not separate queries):
       *   - Single scan of all_property_ops CTE
       *   - Each operation is processed exactly once
       *   - Parsers return NULL for fields they don't handle
       *
       * (.)* SYNTAX:
       *   - Expands composite type into individual columns
       *   - hafbe_backend.witness_properties has: url, price_feed, bias, block_size,
       *     signing_key, hbd_interest_rate, account_creation_fee
       *   - Each becomes a separate column in parsed_properties
       *
       * PARSER RESPONSIBILITIES:
       *   - parse_witness_set_properties_operation: All fields (modern format)
       *   - parse_witness_update_operation: url, block_size, signing_key, hbd_interest_rate, account_creation_fee
       *   - parse_feed_publish_operation: price_feed, bias only
       *   - parse_pow_witness_properties: signing_key (from work.worker), props
       *   - parse_pow2_witness_properties: signing_key (from new_owner_key), props
       */
      (CASE
        WHEN apo.op_type_id = _op_witness_set_properties THEN
          hafbe_backend.parse_witness_set_properties_operation(apo.value)
        WHEN apo.op_type_id = _op_witness_update THEN
          hafbe_backend.parse_witness_update_operation(apo.value)
        WHEN apo.op_type_id = _op_feed_publish THEN
          hafbe_backend.parse_feed_publish_operation(apo.value)
        WHEN apo.op_type_id = _op_pow THEN
          hafbe_backend.parse_pow_witness_properties(apo.value)
        WHEN apo.op_type_id = _op_pow2 THEN
          hafbe_backend.parse_pow2_witness_properties(apo.value)
      END).*
    FROM all_property_ops apo
  ),

  /*
   * ===================================================================================
   * CTE: latest_properties
   * ===================================================================================
   * PURPOSE: Select the latest non-NULL value for each property per witness.
   *
   * PATTERN: "FIRST NON-NULL" using FIRST_VALUE with custom ordering:
   *   ORDER BY CASE WHEN field IS NOT NULL THEN 0 ELSE 1 END, operation_id DESC
   *   - Prioritizes non-NULL values (0 sorts before 1)
   *   - Among non-NULLs, takes the latest by operation_id
   *
   * SPECIAL CASES:
   *   - created_block: uses MIN (earliest operation = witness creation)
   *   - signing_key: uses priority system (see SIGNING_KEY PRIORITY below)
   *
   * SIGNING_KEY PRIORITY:
   *   witness_update and witness_set_properties are explicit key updates,
   *   while pow/pow2 only set initial keys when a witness is first created.
   *   Priority: witness_update/witness_set_properties (LATEST) > pow/pow2 (FIRST)
   *
   *   CRITICAL: pow/pow2 signing_key should ONLY be used for initial INSERT,
   *   never to UPDATE an existing key set by witness_update. We track this with
   *   signing_key_from_priority flag, and only include pow signing_key when
   *   no priority operation has set a key (for INSERT of new witnesses).
   *
   * WINDOW CLAUSE: Named windows for readability and to avoid repetition.
   */
  latest_properties AS (
    SELECT DISTINCT ON (witness)
      witness,
      /*
       * FIRST_VALUE + custom ORDER BY pattern explained:
       * - FIRST_VALUE returns the first value in the window frame
       * - Our ORDER BY puts non-NULL values first (0 < 1), then sorts by operation_id DESC
       * - Result: We get the LATEST non-NULL value for each property
       * - If all values are NULL, we get NULL (which is correct - no data available)
       */
      FIRST_VALUE(url) OVER w_url                         AS url,
      FIRST_VALUE(price_feed) OVER w_price_feed           AS price_feed,
      FIRST_VALUE(bias) OVER w_price_feed                 AS bias,
      /*
       * CRITICAL: Only set price_feed_block when price_feed is non-NULL.
       * Without this check, batches with only witness_update (no feed_publish) would
       * incorrectly set price_feed_block from the witness_update's block_num, causing
       * feed_updated_at to be overwritten with the wrong timestamp.
       */
      CASE WHEN FIRST_VALUE(price_feed) OVER w_price_feed IS NOT NULL
           THEN FIRST_VALUE(block_num) OVER w_price_feed
      END                                                 AS price_feed_block,
      FIRST_VALUE(block_size) OVER w_block_size           AS block_size,
      /*
       * SIGNING_KEY SEPARATION:
       * We split signing_key into two columns based on operation type because they have
       * different semantics:
       *
       * signing_key_priority (from witness_update/witness_set_properties):
       *   - Explicit key updates initiated by the witness owner
       *   - Should ALWAYS take precedence over pow keys
       *   - Used for both INSERT and UPDATE operations
       *   - Takes LATEST value (operation_id DESC) - newer updates win
       *
       * signing_key_pow (from pow/pow2):
       *   - Initial key set when witness first mines a block
       *   - Should ONLY be used for INSERT of new witnesses
       *   - Should NEVER overwrite an existing key set by witness_update
       *   - Takes FIRST value (operation_id ASC) - original mining key
       *
       * WHY THIS MATTERS:
       *   Without this separation, a batch containing only pow operations would
       *   overwrite a witness's current signing_key with the old pow key.
       *   Example: Witness updates key via witness_update at block 1M, then has
       *   a pow operation processed in a later batch at block 2M - the pow key
       *   would incorrectly replace the witness_update key.
       */
      -- signing_key from priority operations only (witness_update/witness_set_properties)
      -- The CASE WHEN filters to only these op types; other ops return NULL
      -- This is used for UPDATE - only priority ops can change an existing key
      FIRST_VALUE(CASE WHEN op_type_id IN (_op_witness_update, _op_witness_set_properties)
                       THEN signing_key END) OVER w_signing_key_update AS signing_key_priority,
      -- signing_key from pow/pow2 - only used for INSERT when no existing key
      -- The CASE WHEN filters to only pow ops; other ops return NULL
      FIRST_VALUE(CASE WHEN op_type_id IN (_op_pow, _op_pow2)
                       THEN signing_key END) OVER w_signing_key_pow AS signing_key_pow,
      FIRST_VALUE(hbd_interest_rate) OVER w_hbd           AS hbd_interest_rate,
      FIRST_VALUE(account_creation_fee) OVER w_fee        AS account_creation_fee,
      /*
       * created_block uses MIN (not FIRST_VALUE) because:
       * - The witness was "created" at their FIRST operation, not their latest
       * - MIN gives us the earliest block_num where this witness appeared
       */
      MIN(block_num) OVER (PARTITION BY witness)          AS created_block
    FROM parsed_properties
    WHERE witness IS NOT NULL
    /*
     * WINDOW DEFINITIONS:
     * Each window uses the same "FIRST NON-NULL" pattern with field-specific filtering:
     *   PARTITION BY witness - group operations by witness
     *   ORDER BY CASE WHEN field IS NOT NULL THEN 0 ELSE 1 END - non-NULLs first
     *   operation_id DESC/ASC - among non-NULLs, take latest/earliest
     */
    WINDOW
      -- Standard mutable properties: take LATEST non-NULL value
      w_url         AS (PARTITION BY witness ORDER BY CASE WHEN url IS NOT NULL THEN 0 ELSE 1 END, operation_id DESC),
      w_price_feed  AS (PARTITION BY witness ORDER BY CASE WHEN price_feed IS NOT NULL THEN 0 ELSE 1 END, operation_id DESC),
      w_block_size  AS (PARTITION BY witness ORDER BY CASE WHEN block_size IS NOT NULL THEN 0 ELSE 1 END, operation_id DESC),
      /*
       * signing_key windows use COMPOUND filtering:
       * 1. CASE filters by BOTH op_type AND non-NULL value (both must match for 0)
       * 2. For w_signing_key_update: operation_id DESC = take LATEST priority key
       * 3. For w_signing_key_pow: operation_id ASC = take FIRST/ORIGINAL pow key
       *
       * The ASC vs DESC distinction matters because:
       * - Priority keys (witness_update): Witness intentionally changing their key, latest wins
       * - Pow keys: Original mining key from when witness first appeared, first wins
       */
      w_signing_key_update AS (PARTITION BY witness ORDER BY
        CASE WHEN op_type_id IN (_op_witness_update, _op_witness_set_properties) AND signing_key IS NOT NULL THEN 0 ELSE 1 END,
        operation_id DESC),
      w_signing_key_pow AS (PARTITION BY witness ORDER BY
        CASE WHEN op_type_id IN (_op_pow, _op_pow2) AND signing_key IS NOT NULL THEN 0 ELSE 1 END,
        operation_id ASC),
      w_hbd         AS (PARTITION BY witness ORDER BY CASE WHEN hbd_interest_rate IS NOT NULL THEN 0 ELSE 1 END, operation_id DESC),
      w_fee         AS (PARTITION BY witness ORDER BY CASE WHEN account_creation_fee IS NOT NULL THEN 0 ELSE 1 END, operation_id DESC)
    ORDER BY witness
  ),

  /*
   * ===================================================================================
   * CTE: resolved_properties
   * ===================================================================================
   * PURPOSE: Late binding - resolve account IDs on smallest result set.
   * Also lookup timestamps from blocks_view for feed_updated_at and created.
   *
   * WHY LATE BINDING:
   *   We resolve witness names to account IDs HERE (not earlier) because:
   *   1. latest_properties has ~1 row per witness (greatly reduced from all operations)
   *   2. The correlated subquery to accounts_view is expensive
   *   3. Running it on the smallest result set minimizes total lookup cost
   *
   * SIGNING_KEY HANDLING:
   *   - signing_key_priority: from witness_update/witness_set_properties (can UPDATE)
   *   - signing_key_pow: from pow/pow2 (only for INSERT, never UPDATE)
   *   - signing_key_for_insert: COALESCE of both (for new witnesses)
   */
  resolved_properties AS (
    SELECT
      /*
       * Correlated subquery for account ID lookup:
       * Returns NULL if witness name not found (filtered out in INSERT WHERE clause)
       */
      (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = lp.witness) AS witness_id,
      lp.url,
      lp.price_feed,
      lp.bias,
      /*
       * Timestamp lookups from blocks_view:
       * We store block_num in CTEs but need timestamp for final storage.
       * These subqueries are efficient because they use primary key lookup on blocks_view.
       */
      (SELECT hb.created_at FROM hive.blocks_view hb WHERE hb.num = lp.price_feed_block) AS feed_updated_at,
      lp.block_size,
      /*
       * signing_key_priority: Pass through for use in UPDATE clause subquery.
       * This is NULL when no witness_update/witness_set_properties ops in this batch.
       */
      lp.signing_key_priority,
      /*
       * signing_key_for_insert: Used as the INSERT value for signing_key column.
       * COALESCE order: priority key first, pow key as fallback.
       *
       * For NEW witnesses (INSERT): May come from either source
       * For EXISTING witnesses (UPDATE): The UPDATE clause will use signing_key_priority
       *   directly via subquery, ignoring this value.
       */
      COALESCE(lp.signing_key_priority, lp.signing_key_pow) AS signing_key_for_insert,
      lp.hbd_interest_rate,
      lp.account_creation_fee,
      (SELECT hb.created_at FROM hive.blocks_view hb WHERE hb.num = lp.created_block) AS created
    FROM latest_properties lp
  )

  /*
   * ===================================================================================
   * UPSERT: Insert new witnesses with properties, update existing ones.
   * ===================================================================================
   *
   * COALESCE PATTERNS (critical for understanding UPDATE behavior):
   *
   *   Pattern 1 - Mutable fields: COALESCE(EXCLUDED.field, cw.field)
   *     - EXCLUDED contains the new value from this batch
   *     - cw contains the existing value in the table
   *     - New value wins if non-NULL, otherwise keep existing
   *     - Used for: url, price_feed, bias, feed_updated_at, block_size, hbd_interest_rate, account_creation_fee
   *
   *   Pattern 2 - Immutable fields: COALESCE(cw.field, EXCLUDED.field)
   *     - Existing value wins if non-NULL, otherwise use new
   *     - Used for: created (witness creation time should never change)
   *
   *   Pattern 3 - signing_key (special): Uses subquery to get signing_key_priority
   *     - Cannot use EXCLUDED because it contains signing_key_for_insert (includes pow)
   *     - Must query resolved_properties to get signing_key_priority (excludes pow)
   *     - See detailed explanation below
   *
   * SIGNING_KEY SPECIAL HANDLING:
   *   Problem: EXCLUDED.signing_key contains signing_key_for_insert which includes pow keys.
   *   We cannot use COALESCE(EXCLUDED.signing_key, cw.signing_key) because:
   *   - If batch has ONLY pow ops, EXCLUDED.signing_key would be the pow key
   *   - This would overwrite an existing key set by witness_update (WRONG!)
   *
   *   Solution: Use a subquery to look up signing_key_priority directly:
   *   - signing_key_priority is NULL when no witness_update/witness_set_properties in batch
   *   - COALESCE(signing_key_priority, cw.signing_key) preserves existing key when NULL
   *   - Only explicit witness_update/witness_set_properties can change the key
   */
  INSERT INTO hafbe_app.current_witnesses AS cw (
    witness_id, url, price_feed, bias, feed_updated_at,
    block_size, signing_key, hbd_interest_rate, account_creation_fee, created
  )
  SELECT
    rp.witness_id, rp.url, rp.price_feed, rp.bias, rp.feed_updated_at,
    /*
     * For INSERT: Use signing_key_for_insert which includes both priority and pow keys.
     * New witnesses may have their initial key set by either witness_update or pow.
     */
    rp.block_size, rp.signing_key_for_insert, rp.hbd_interest_rate, rp.account_creation_fee, rp.created
  FROM resolved_properties rp
  WHERE rp.witness_id IS NOT NULL
  ON CONFLICT ON CONSTRAINT pk_current_witnesses DO UPDATE SET
    /*
     * MUTABLE FIELDS: New value takes precedence (EXCLUDED first in COALESCE)
     * If this batch has no update for a field (NULL), keep the existing value.
     */
    url                  = COALESCE(EXCLUDED.url, cw.url),
    price_feed           = COALESCE(EXCLUDED.price_feed, cw.price_feed),
    bias                 = COALESCE(EXCLUDED.bias, cw.bias),
    feed_updated_at      = COALESCE(EXCLUDED.feed_updated_at, cw.feed_updated_at),
    block_size           = COALESCE(EXCLUDED.block_size, cw.block_size),
    /*
     * SIGNING_KEY: Special handling to prevent pow keys from overwriting existing keys.
     *
     * WHY SUBQUERY: We cannot use EXCLUDED.signing_key because it contains
     * signing_key_for_insert which may include pow keys. We need signing_key_priority
     * which ONLY contains keys from witness_update/witness_set_properties.
     *
     * BEHAVIOR:
     *   - If batch has witness_update: signing_key_priority is non-NULL, key is updated
     *   - If batch has only pow/pow2: signing_key_priority is NULL, existing key preserved
     *   - If batch has only feed_publish: signing_key_priority is NULL, existing key preserved
     *
     * This ensures pow operations can set the INITIAL key (on INSERT) but can never
     * OVERWRITE a key that was set by an explicit witness_update operation.
     */
    signing_key          = COALESCE(
      (SELECT rp2.signing_key_priority FROM resolved_properties rp2 WHERE rp2.witness_id = EXCLUDED.witness_id),
      cw.signing_key
    ),
    hbd_interest_rate    = COALESCE(EXCLUDED.hbd_interest_rate, cw.hbd_interest_rate),
    account_creation_fee = COALESCE(EXCLUDED.account_creation_fee, cw.account_creation_fee),
    /*
     * IMMUTABLE FIELD: Existing value takes precedence (cw first in COALESCE)
     * The witness creation time should never change once set.
     */
    created              = COALESCE(cw.created, EXCLUDED.created);


  /*
   * ===================================================================================
   * SECTION 2: Update Witness Version
   * ===================================================================================
   * Parse version from block extensions using parser function.
   * This comes from blocks_view, not operations.
   * The version is stored in the extensions field when a witness produces a block.
   *
   * BUG FIX: Filter NULL versions BEFORE ROW_NUMBER, not after.
   *
   * PROBLEM WITH OLD CODE:
   *   1. Took the latest block with extensions (ROW_NUMBER first)
   *   2. Then checked if version IS NOT NULL
   *   3. If latest block had only hardfork_version_vote (no version), witness was skipped
   *   4. Even though earlier blocks might have had version data
   *
   * CORRECT APPROACH:
   *   1. Parse version for all blocks with extensions
   *   2. Filter to only blocks where version IS NOT NULL
   *   3. THEN take the latest block with actual version data
   *
   * WHY EXTENSIONS CAN HAVE NULL VERSION:
   *   Block extensions can contain different types of data:
   *   - {"type": "version", "value": "1.27.5"}        -> version = "1.27.5"
   *   - {"type": "hardfork_version_vote", "value": ...} -> version = NULL
   *   A block may have extensions but no version entry.
   */
  UPDATE hafbe_app.current_witnesses cw SET version = w_node.version
  FROM (
    SELECT witness_id, version
    FROM (
      SELECT
        witness_id,
        version,
        /*
         * ROW_NUMBER assigns 1 to the latest block (ORDER BY num DESC)
         * for each witness. We take row_n = 1 to get the most recent version.
         */
        ROW_NUMBER() OVER (PARTITION BY witness_id ORDER BY num DESC) AS row_n
      FROM (
        /*
         * Inner subquery: Extract version from blocks with extensions.
         * parse_block_version returns NULL if extensions don't contain version type.
         */
        SELECT
          hbv.producer_account_id AS witness_id,
          hafbe_backend.parse_block_version(hbv.extensions) AS version,
          hbv.num
        FROM hafbe_app.blocks_view hbv
        WHERE hbv.num BETWEEN _from AND _to
          AND hbv.extensions IS NOT NULL
      ) with_version
      /*
       * CRITICAL: Filter NULLs BEFORE ROW_NUMBER ranking.
       * This ensures we rank only blocks that actually have version data.
       */
      WHERE version IS NOT NULL
    ) ranked
    WHERE row_n = 1
  ) w_node
  WHERE cw.witness_id = w_node.witness_id;


  /*
   * ===================================================================================
   * SECTION 3: Update Missed Blocks
   * ===================================================================================
   * Count producer_missed_operation events per witness.
   * Uses ADDITIVE UPSERT pattern (adds to existing count).
   *
   * WHY SEPARATE FROM SECTION 1:
   *   missed_blocks requires ADDITIVE logic (cw + EXCLUDED), not replacement logic.
   *   Section 1 properties use COALESCE(EXCLUDED, cw) - new value replaces old.
   *   Here we SUM the new count with existing count across batches.
   */
  WITH select_ops_with_missed AS MATERIALIZED (
    /*
     * Get witness names from producer_missed operations.
     * hive.get_impacted_accounts extracts the witness name from the operation body.
     * WHY MATERIALIZED: Prevents multiple calls to get_impacted_accounts.
     */
    SELECT w AS witness
    FROM hafbe_app.operations_view ov
    CROSS JOIN LATERAL hive.get_impacted_accounts(ov.body::hafd.operation) AS w
    WHERE ov.op_type_id = _op_producer_missed
      AND ov.block_num BETWEEN _from AND _to
  ),

  count_missed AS (
    /*
     * Aggregate: Count missed blocks per witness in this batch.
     * A witness may miss multiple blocks in a single processing batch.
     */
    SELECT
      COUNT(*) AS missed_blocks,
      witness
    FROM select_ops_with_missed
    GROUP BY witness
  )

  /*
   * ADDITIVE UPSERT PATTERN:
   *   missed_blocks = COALESCE(cw.missed_blocks, 0) + EXCLUDED.missed_blocks
   *
   * WHY ADDITIVE (different from Section 1):
   *   - Each batch adds to the running total, not replaces it
   *   - If witness has no prior record, COALESCE handles NULL -> 0
   *   - EXCLUDED.missed_blocks contains count from THIS batch only
   *
   * EXAMPLE:
   *   Batch 1: Witness misses 3 blocks -> missed_blocks = 0 + 3 = 3
   *   Batch 2: Witness misses 2 blocks -> missed_blocks = 3 + 2 = 5
   */
  INSERT INTO hafbe_app.current_witnesses AS cw (witness_id, missed_blocks)
  SELECT
    (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = cm.witness),
    cm.missed_blocks
  FROM count_missed cm
  ON CONFLICT ON CONSTRAINT pk_current_witnesses DO UPDATE SET
    missed_blocks = COALESCE(cw.missed_blocks, 0) + EXCLUDED.missed_blocks;


  /*
   * ===================================================================================
   * SECTION 4: Update Last Created Block
   * ===================================================================================
   * Track the most recent block produced by each witness.
   *
   * WHY SIMPLE UPDATE (not UPSERT):
   *   - Witnesses must already exist in current_witnesses from Section 1
   *   - We just update the last_created_block_num field
   *   - No need for INSERT - only witnesses who've produced blocks matter here
   *
   * WHY MAX() NOT UPSERT PATTERN:
   *   - We only care about the LATEST block in this batch
   *   - MAX(bv.num) gives us the highest block number per witness
   *   - Since batches process in order, this will always be >= existing value
   */
  UPDATE hafbe_app.current_witnesses cw SET last_created_block_num = blocks.last_created_block_num
  FROM (
    SELECT
      bv.producer_account_id AS witness_id,
      /*
       * MAX gives us the latest block produced by this witness in the batch.
       * A witness may produce multiple blocks per batch (21 witnesses, 3-second blocks).
       */
      MAX(bv.num)            AS last_created_block_num
    FROM hafbe_app.blocks_view bv
    WHERE bv.num BETWEEN _from AND _to
    GROUP BY bv.producer_account_id
  ) blocks
  WHERE cw.witness_id = blocks.witness_id;

END $$;

RESET ROLE;
