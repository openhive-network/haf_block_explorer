SET ROLE hafbe_owner;

/*
 * Witness Stats Parsers
 *
 * Helper type and functions for parsing witness property operations.
 * Used by hafbe_app.process_witness_stats() to extract witness configuration
 * from operation JSON bodies.
 *
 * Each parser extracts all available properties from a specific operation type.
 * Witness name is NOT extracted here - it comes from witness_prop_op_view
 * via hive.get_impacted_accounts().
 *
 * JSON parsing is done INSIDE parsers to avoid repeated casting in the main query.
 */

DROP TYPE IF EXISTS hafbe_backend.witness_properties CASCADE;
CREATE TYPE hafbe_backend.witness_properties AS (
  url                  TEXT,      -- witness URL
  price_feed           NUMERIC,   -- pre-computed: base.amount / quote.amount
  bias                 NUMERIC,   -- pre-computed: quote.amount - 1000
  block_size           INT,       -- maximum_block_size
  signing_key          TEXT,      -- block signing key
  hbd_interest_rate    INT,       -- HBD interest rate (basis points)
  account_creation_fee INT        -- account creation fee (amount in satoshis)
);


/*
 * ===================================================================================
 * parse_witness_set_properties_operation
 * ===================================================================================
 * PURPOSE: Parse witness_set_properties_operation (modern witness configuration).
 *
 * JSON STRUCTURE:
 *   { "owner": "witness-name", "props": "<serialized key-value pairs>" }
 *
 * The 'props' field is a serialized string that hive.extract_set_witness_properties()
 * decodes into (prop_name, prop_value) rows.
 *
 * PROPERTY NAMES:
 *   - url: Witness URL
 *   - hbd_exchange_rate: Price feed JSON { "base": {"amount": X}, "quote": {"amount": Y} }
 *   - maximum_block_size: Max block size
 *   - new_signing_key or key: Block signing key
 *   - hbd_interest_rate: HBD interest rate
 *   - account_creation_fee: Account creation fee JSON
 *
 * PRICE FEED CALCULATION (done here to avoid JSON parsing in main query):
 *   price_feed = base.amount / quote.amount
 *   bias = quote.amount - 1000
 *
 * RETURNS: witness_properties with all extractable fields populated.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.parse_witness_set_properties_operation(
    _value JSONB
)
RETURNS hafbe_backend.witness_properties
LANGUAGE 'plpgsql' STABLE
AS $$
DECLARE
  __props_text     TEXT := _value->>'props';
  __props          JSONB;
  __exchange_rate  JSONB;
  __base_amount    NUMERIC;
  __quote_amount   NUMERIC;
  __result         hafbe_backend.witness_properties;
BEGIN
  /*
   * Call extract_set_witness_properties ONCE and convert to JSONB object.
   * This avoids calling the function 7 times for each property lookup.
   */
  SELECT jsonb_object_agg(prop_name, prop_value) INTO __props
  FROM hive.extract_set_witness_properties(__props_text);

  -- Extract exchange rate and compute price_feed/bias
  __exchange_rate := __props -> 'hbd_exchange_rate';
  IF __exchange_rate IS NOT NULL THEN
    __base_amount  := (__exchange_rate -> 'base' ->> 'amount')::NUMERIC;
    __quote_amount := (__exchange_rate -> 'quote' ->> 'amount')::NUMERIC;
  END IF;

  -- Build result from the aggregated properties object
  __result := (
    __props ->> 'url',
    CASE WHEN __quote_amount > 0 THEN __base_amount / __quote_amount END,  -- price_feed
    CASE WHEN __quote_amount IS NOT NULL THEN __quote_amount - 1000 END,   -- bias
    (__props ->> 'maximum_block_size')::INT,
    COALESCE(__props ->> 'new_signing_key', __props ->> 'key'),            -- signing_key
    (__props ->> 'hbd_interest_rate')::INT,
    (__props -> 'account_creation_fee' ->> 'amount')::INT
  );

  RETURN __result;
END
$$;


/*
 * ===================================================================================
 * parse_witness_update_operation
 * ===================================================================================
 * PURPOSE: Parse witness_update_operation (legacy witness configuration).
 *
 * JSON STRUCTURE:
 *   {
 *     "owner": "witness-name",
 *     "url": "https://...",
 *     "block_signing_key": "STM...",
 *     "props": {
 *       "account_creation_fee": { "amount": "...", "nai": "...", ... },
 *       "maximum_block_size": 131072,
 *       "hbd_interest_rate": 0
 *     },
 *     "fee": { ... }
 *   }
 *
 * NOTE: This format is older than witness_set_properties. The 'props' field
 * is already JSON (not serialized string), accessed with -> operator.
 * Does NOT contain exchange_rate (price feed comes from feed_publish_operation).
 *
 * RETURNS: witness_properties with extractable fields populated.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.parse_witness_update_operation(
    _value JSONB
)
RETURNS hafbe_backend.witness_properties
LANGUAGE 'plpgsql' STABLE
AS $$
DECLARE
  __result hafbe_backend.witness_properties;
BEGIN
  __result := (
    _value->>'url',
    NULL,  -- price_feed: not in witness_update (comes from feed_publish)
    NULL,  -- bias: not in witness_update
    (_value->'props'->>'maximum_block_size')::INT,
    _value->>'block_signing_key',
    (_value->'props'->>'hbd_interest_rate')::INT,
    (_value->'props'->'account_creation_fee'->>'amount')::INT
  );

  RETURN __result;
END
$$;


/*
 * ===================================================================================
 * parse_feed_publish_operation
 * ===================================================================================
 * PURPOSE: Parse feed_publish_operation (price feed update).
 *
 * JSON STRUCTURE:
 *   {
 *     "publisher": "witness-name",
 *     "exchange_rate": {
 *       "base": { "amount": "250", "nai": "@@000000013", ... },
 *       "quote": { "amount": "1000", "nai": "@@000000021", ... }
 *     }
 *   }
 *
 * PRICE FEED CALCULATION (done here to avoid JSON parsing in main query):
 *   price_feed = base.amount / quote.amount
 *   bias = quote.amount - 1000
 *
 * RETURNS: witness_properties with price_feed and bias populated.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.parse_feed_publish_operation(
    _value JSONB
)
RETURNS hafbe_backend.witness_properties
LANGUAGE 'plpgsql' STABLE
AS $$
DECLARE
  __base_amount  NUMERIC := (_value -> 'exchange_rate' -> 'base' ->> 'amount')::NUMERIC;
  __quote_amount NUMERIC := (_value -> 'exchange_rate' -> 'quote' ->> 'amount')::NUMERIC;
  __result       hafbe_backend.witness_properties;
BEGIN
  __result := (
    NULL,  -- url
    CASE WHEN __quote_amount > 0 THEN __base_amount / __quote_amount END,  -- price_feed
    CASE WHEN __quote_amount IS NOT NULL THEN __quote_amount - 1000 END,   -- bias
    NULL,  -- block_size
    NULL,  -- signing_key
    NULL,  -- hbd_interest_rate
    NULL   -- account_creation_fee
  );

  RETURN __result;
END
$$;


/*
 * ===================================================================================
 * parse_pow_witness_properties
 * ===================================================================================
 * PURPOSE: Parse pow_operation for witness signing key and initial properties.
 *
 * JSON STRUCTURE:
 *   {
 *     "worker_account": "witness-name",
 *     "block_id": "...",
 *     "nonce": ...,
 *     "work": { "worker": "STM..." },
 *     "props": {
 *       "account_creation_fee": { ... },
 *       "maximum_block_size": 131072,
 *       "hbd_interest_rate": 0
 *     }
 *   }
 *
 * NOTE: signing_key comes from work.worker field.
 * This is a fallback for witnesses that only have pow operations.
 * Does NOT contain exchange_rate (price feed comes from feed_publish_operation).
 *
 * RETURNS: witness_properties with signing_key and props populated.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.parse_pow_witness_properties(
    _value JSONB
)
RETURNS hafbe_backend.witness_properties
LANGUAGE 'plpgsql' STABLE
AS $$
DECLARE
  __result hafbe_backend.witness_properties;
BEGIN
  __result := (
    NULL,  -- url
    NULL,  -- price_feed: not in pow (comes from feed_publish)
    NULL,  -- bias: not in pow
    (_value->'props'->>'maximum_block_size')::INT,
    _value->'work'->>'worker',  -- signing_key from work.worker
    (_value->'props'->>'hbd_interest_rate')::INT,
    (_value->'props'->'account_creation_fee'->>'amount')::INT
  );

  RETURN __result;
END
$$;


/*
 * ===================================================================================
 * parse_pow2_witness_properties
 * ===================================================================================
 * PURPOSE: Parse pow2_operation for witness signing key and initial properties.
 *
 * JSON STRUCTURE:
 *   {
 *     "work": {
 *       "type": "pow2",
 *       "value": {
 *         "input": { "worker_account": "witness-name", ... },
 *         ...
 *       }
 *     },
 *     "new_owner_key": "STM...",
 *     "props": {
 *       "account_creation_fee": { ... },
 *       "maximum_block_size": 131072,
 *       "hbd_interest_rate": 0
 *     }
 *   }
 *
 * NOTE: signing_key comes from new_owner_key field (different from pow).
 * Does NOT contain exchange_rate (price feed comes from feed_publish_operation).
 *
 * RETURNS: witness_properties with signing_key and props populated.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.parse_pow2_witness_properties(
    _value JSONB
)
RETURNS hafbe_backend.witness_properties
LANGUAGE 'plpgsql' STABLE
AS $$
DECLARE
  __result hafbe_backend.witness_properties;
BEGIN
  __result := (
    NULL,  -- url
    NULL,  -- price_feed: not in pow2 (comes from feed_publish)
    NULL,  -- bias: not in pow2
    (_value->'props'->>'maximum_block_size')::INT,
    _value->>'new_owner_key',  -- signing_key from new_owner_key
    (_value->'props'->>'hbd_interest_rate')::INT,
    (_value->'props'->'account_creation_fee'->>'amount')::INT
  );

  RETURN __result;
END
$$;


/*
 * ===================================================================================
 * parse_block_version
 * ===================================================================================
 * PURPOSE: Extract witness version from block extensions.
 *
 * BLOCK EXTENSIONS STRUCTURE (array with type/value objects):
 *   [
 *     { "type": "version", "value": "1.27.5" },
 *     { "type": "...", "value": "..." }
 *   ]
 *
 * The version entry can be at position 0 or 1 in the extensions array.
 * We check the 'type' field to find it.
 *
 * RETURNS: Version string if found, NULL otherwise.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.parse_block_version(
    _extensions JSONB
)
RETURNS TEXT
LANGUAGE 'plpgsql' STABLE
AS $$
BEGIN
  IF _extensions IS NULL THEN
    RETURN NULL;
  END IF;

  -- Check position 0 first
  IF _extensions -> 0 ->> 'type' = 'version' THEN
    RETURN _extensions -> 0 ->> 'value';
  END IF;

  -- Check position 1
  RETURN _extensions -> 1 ->> 'value';
END
$$;


RESET ROLE;
