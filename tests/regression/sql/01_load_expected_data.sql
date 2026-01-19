-- =============================================================================
-- HAF Block Explorer Regression Test - Data Loading Functions
-- =============================================================================
--
-- PURPOSE:
--   Functions to load expected account and witness data from hived JSON
--   snapshots into the hafbe_test schema for comparison.
--
-- FUNCTIONS:
--   hafbe_test.load_expected_account_stats(jsonb) - Load single account
--   hafbe_test.load_expected_witness_props(jsonb) - Load single witness
--
-- =============================================================================

SET ROLE hafbe_owner;

-- =============================================================================
-- Account Loading
-- =============================================================================

/*
 * load_expected_account_stats: Parse and insert one account from hived JSON.
 *
 * JSON STRUCTURE (from database_api.list_accounts):
 *   {
 *     "id": 12345,
 *     "name": "account-name",
 *     "witnesses_voted_for": 5,
 *     "can_vote": true,
 *     "mined": false,
 *     "last_account_recovery": "1970-01-01T00:00:00",
 *     "created": "2016-04-01T00:00:00",
 *     "proxy": "",
 *     "last_vote_time": "2016-05-01T00:00:00",
 *     "recovery_account": "steem"
 *   }
 *
 * FIELD MAPPINGS:
 *   - proxy: Account name converted to ID via accounts_view lookup
 *   - Empty proxy ("") resolves to NULL
 */
CREATE OR REPLACE FUNCTION hafbe_test.load_expected_account_stats(_account_data JSONB)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS $$
BEGIN
  INSERT INTO hafbe_test.expected_account_stats (
    account_id,
    witnesses_voted_for,
    can_vote,
    mined,
    last_account_recovery,
    created,
    proxy,
    last_vote_time,
    recovery_account
  )
  SELECT
    (_account_data ->> 'id')::INT,
    (_account_data ->> 'witnesses_voted_for')::INT,
    (_account_data ->> 'can_vote')::BOOLEAN,
    (_account_data ->> 'mined')::BOOLEAN,
    (_account_data ->> 'last_account_recovery')::TIMESTAMP,
    (_account_data ->> 'created')::TIMESTAMP,
    (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = (_account_data ->> 'proxy')),
    (_account_data ->> 'last_vote_time')::TIMESTAMP,
    (_account_data ->> 'recovery_account')::TEXT;
END
$$;

-- =============================================================================
-- Witness Loading
-- =============================================================================

/*
 * load_expected_witness_props: Parse and insert one witness from hived JSON.
 *
 * JSON STRUCTURE (from database_api.list_witnesses):
 *   {
 *     "owner": "witness-name",
 *     "url": "https://...",
 *     "votes": "12345678901234567",
 *     "total_missed": 42,
 *     "last_confirmed_block_num": 5000000,
 *     "signing_key": "STM...",
 *     "running_version": "1.27.5",
 *     "created": "2016-04-01T00:00:00",
 *     "props": {
 *       "account_creation_fee": "3.000 HIVE",
 *       "maximum_block_size": 65536,
 *       "hbd_interest_rate": 1000
 *     },
 *     "hbd_exchange_rate": {
 *       "base": "0.500 HBD",
 *       "quote": "1.000 HIVE"
 *     },
 *     "last_hbd_exchange_update": "2024-01-01T00:00:00"
 *   }
 *
 * FIELD MAPPINGS:
 *   - owner: Converted to witness_id via accounts_view lookup
 *   - votes: Stored as vests (BIGINT)
 *   - total_missed: Stored as missed_blocks
 *   - running_version: Stored as version
 *   - account_creation_fee: Extracted numeric amount (e.g., "3.000 HIVE" -> 3000)
 *   - price_feed: Calculated as base.amount / quote.amount
 */
CREATE OR REPLACE FUNCTION hafbe_test.load_expected_witness_props(_witness_data JSONB)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS $$
DECLARE
  __base_amount  NUMERIC;
  __quote_amount NUMERIC;
  __price_feed   NUMERIC;
BEGIN
  -- Calculate price_feed = base / quote (matching hafbe_app calculation)
  __base_amount  := (REGEXP_REPLACE(_witness_data -> 'hbd_exchange_rate' ->> 'base', '[^0-9.]', '', 'g'))::NUMERIC;
  __quote_amount := (REGEXP_REPLACE(_witness_data -> 'hbd_exchange_rate' ->> 'quote', '[^0-9.]', '', 'g'))::NUMERIC;
  __price_feed   := CASE WHEN __quote_amount > 0 THEN __base_amount / __quote_amount ELSE NULL END;

  INSERT INTO hafbe_test.expected_witness_props (
    witness_id,
    url,
    vests,
    missed_blocks,
    last_confirmed_block_num,
    signing_key,
    version,
    account_creation_fee,
    block_size,
    hbd_interest_rate,
    price_feed,
    feed_updated_at,
    created
  )
  SELECT
    (SELECT av.id FROM hive.accounts_view av WHERE av.name = (_witness_data ->> 'owner')),
    (_witness_data ->> 'url')::TEXT,
    (_witness_data ->> 'votes')::BIGINT,
    (_witness_data ->> 'total_missed')::INT,
    (_witness_data ->> 'last_confirmed_block_num')::INT,
    (_witness_data ->> 'signing_key')::TEXT,
    (_witness_data ->> 'running_version')::TEXT,
    (REGEXP_REPLACE(_witness_data -> 'props' ->> 'account_creation_fee', '[^0-9]', '', 'g'))::INT,
    (_witness_data -> 'props' ->> 'maximum_block_size')::INT,
    (_witness_data -> 'props' ->> 'hbd_interest_rate')::INT,
    __price_feed,
    (_witness_data ->> 'last_hbd_exchange_update')::TIMESTAMP,
    (_witness_data ->> 'created')::TIMESTAMP;
END
$$;

-- =============================================================================
-- Comparison Types
-- =============================================================================

/*
 * account_comparison_type: Return type for get_account_comparison().
 * Returns two rows: expected values (row 1) and computed values (row 2).
 */
DROP TYPE IF EXISTS hafbe_test.account_comparison_type CASCADE;
CREATE TYPE hafbe_test.account_comparison_type AS (
  account_id            INT,
  witnesses_voted_for   INT,
  can_vote              BOOLEAN,
  mined                 BOOLEAN,
  last_account_recovery TIMESTAMP,
  created               TIMESTAMP,
  proxy                 INT,
  last_vote_time        TIMESTAMP,
  recovery_account      TEXT
);

/*
 * witness_comparison_type: Return type for get_witness_comparison().
 * Returns two rows: expected values (row 1) and computed values (row 2).
 */
DROP TYPE IF EXISTS hafbe_test.witness_comparison_type CASCADE;
CREATE TYPE hafbe_test.witness_comparison_type AS (
  witness_id             INT,
  url                    TEXT,
  vests                  BIGINT,
  missed_blocks          INT,
  last_confirmed_block_num INT,
  signing_key            TEXT,
  version                TEXT,
  account_creation_fee   INT,
  block_size             INT,
  hbd_interest_rate      INT,
  price_feed             NUMERIC,
  feed_updated_at        TIMESTAMP,
  created                TIMESTAMP
);

RESET ROLE;
