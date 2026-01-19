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
   */
  WITH all_property_ops AS MATERIALIZED (
    SELECT
      wpov.witness,
      wpov.value,
      wpov.op_type_id,
      wpov.operation_id,
      wpov.block_num
    FROM hafbe_backend.witness_prop_op_view wpov
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
      apo.op_type_id,
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
   *   The CASE expressions filter signing_key by operation type, then:
   *   - w_signing_key_update: takes LATEST from update operations (DESC)
   *   - w_signing_key_pow: takes FIRST from pow operations (ASC)
   *   COALESCE ensures update operations take priority over pow operations.
   *
   * WINDOW CLAUSE: Named windows for readability and to avoid repetition.
   */
  latest_properties AS (
    SELECT DISTINCT ON (witness)
      witness,
      FIRST_VALUE(url) OVER w_url                         AS url,
      FIRST_VALUE(price_feed) OVER w_price_feed           AS price_feed,
      FIRST_VALUE(bias) OVER w_price_feed                 AS bias,
      FIRST_VALUE(block_num) OVER w_price_feed            AS price_feed_block,
      FIRST_VALUE(block_size) OVER w_block_size           AS block_size,
      -- signing_key priority: update operations (LATEST) > pow operations (FIRST)
      COALESCE(
        FIRST_VALUE(CASE WHEN op_type_id IN (_op_witness_update, _op_witness_set_properties)
                         THEN signing_key END) OVER w_signing_key_update,
        FIRST_VALUE(CASE WHEN op_type_id IN (_op_pow, _op_pow2)
                         THEN signing_key END) OVER w_signing_key_pow
      ) AS signing_key,
      FIRST_VALUE(hbd_interest_rate) OVER w_hbd           AS hbd_interest_rate,
      FIRST_VALUE(account_creation_fee) OVER w_fee        AS account_creation_fee,
      MIN(block_num) OVER (PARTITION BY witness)          AS created_block
    FROM parsed_properties
    WHERE witness IS NOT NULL
    WINDOW
      w_url         AS (PARTITION BY witness ORDER BY CASE WHEN url IS NOT NULL THEN 0 ELSE 1 END, operation_id DESC),
      w_price_feed  AS (PARTITION BY witness ORDER BY CASE WHEN price_feed IS NOT NULL THEN 0 ELSE 1 END, operation_id DESC),
      w_block_size  AS (PARTITION BY witness ORDER BY CASE WHEN block_size IS NOT NULL THEN 0 ELSE 1 END, operation_id DESC),
      -- signing_key windows: filter by op_type, then order by NULL-first pattern
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
   */
  resolved_properties AS (
    SELECT
      (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = lp.witness) AS witness_id,
      lp.url,
      lp.price_feed,
      lp.bias,
      (SELECT hb.created_at FROM hive.blocks_view hb WHERE hb.num = lp.price_feed_block) AS feed_updated_at,
      lp.block_size,
      lp.signing_key,
      lp.hbd_interest_rate,
      lp.account_creation_fee,
      (SELECT hb.created_at FROM hive.blocks_view hb WHERE hb.num = lp.created_block) AS created
    FROM latest_properties lp
  )

  /*
   * UPSERT: Insert new witnesses with properties, update existing ones.
   *
   * COALESCE PATTERNS:
   *   - Mutable fields: COALESCE(EXCLUDED.field, cw.field) - new-value-first
   *   - Immutable fields (created): COALESCE(cw.field, EXCLUDED.field) - existing-first
   */
  INSERT INTO hafbe_app.current_witnesses AS cw (
    witness_id, url, price_feed, bias, feed_updated_at,
    block_size, signing_key, hbd_interest_rate, account_creation_fee, created
  )
  SELECT
    rp.witness_id, rp.url, rp.price_feed, rp.bias, rp.feed_updated_at,
    rp.block_size, rp.signing_key, rp.hbd_interest_rate, rp.account_creation_fee, rp.created
  FROM resolved_properties rp
  WHERE rp.witness_id IS NOT NULL
  ON CONFLICT ON CONSTRAINT pk_current_witnesses DO UPDATE SET
    url                  = COALESCE(EXCLUDED.url, cw.url),
    price_feed           = COALESCE(EXCLUDED.price_feed, cw.price_feed),
    bias                 = COALESCE(EXCLUDED.bias, cw.bias),
    feed_updated_at      = COALESCE(EXCLUDED.feed_updated_at, cw.feed_updated_at),
    block_size           = COALESCE(EXCLUDED.block_size, cw.block_size),
    signing_key          = COALESCE(EXCLUDED.signing_key, cw.signing_key),
    hbd_interest_rate    = COALESCE(EXCLUDED.hbd_interest_rate, cw.hbd_interest_rate),
    account_creation_fee = COALESCE(EXCLUDED.account_creation_fee, cw.account_creation_fee),
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
   * Old code took latest block with extensions, then checked if version IS NOT NULL.
   * If latest block had only hardfork_version_vote (no version), witness was skipped.
   * Fix: First filter to blocks with actual version, then take latest.
   */
  UPDATE hafbe_app.current_witnesses cw SET version = w_node.version
  FROM (
    SELECT witness_id, version
    FROM (
      SELECT
        witness_id,
        version,
        ROW_NUMBER() OVER (PARTITION BY witness_id ORDER BY num DESC) AS row_n
      FROM (
        -- Extract version and filter NULLs BEFORE ranking
        SELECT
          hbv.producer_account_id AS witness_id,
          hafbe_backend.parse_block_version(hbv.extensions) AS version,
          hbv.num
        FROM hafbe_app.blocks_view hbv
        WHERE hbv.num BETWEEN _from AND _to
          AND hbv.extensions IS NOT NULL
      ) with_version
      WHERE version IS NOT NULL  -- Filter NULLs BEFORE ROW_NUMBER
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
   */
  WITH select_ops_with_missed AS MATERIALIZED (
    SELECT (SELECT hive.get_impacted_accounts(ov.body_binary)) AS witness
    FROM hafbe_app.operations_view ov
    WHERE ov.op_type_id = _op_producer_missed
      AND ov.block_num BETWEEN _from AND _to
  ),

  count_missed AS (
    SELECT
      COUNT(*) AS missed_blocks,
      witness
    FROM select_ops_with_missed
    GROUP BY witness
  )

  /*
   * ADDITIVE UPSERT PATTERN:
   *   missed_blocks = COALESCE(cw.missed_blocks, 0) + EXCLUDED.missed_blocks
   *   Accumulates missed block count across processing batches.
   *   Uses COALESCE to handle NULL (no default on column).
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
   */
  UPDATE hafbe_app.current_witnesses cw SET last_created_block_num = blocks.last_created_block_num
  FROM (
    SELECT
      bv.producer_account_id AS witness_id,
      MAX(bv.num)            AS last_created_block_num
    FROM hafbe_app.blocks_view bv
    WHERE bv.num BETWEEN _from AND _to
    GROUP BY bv.producer_account_id
  ) blocks
  WHERE cw.witness_id = blocks.witness_id;

END $$;

RESET ROLE;
