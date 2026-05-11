-- =============================================================================
-- Pending HBD Interest Helper
-- =============================================================================
-- Computes pending (unclaimed) HBD interest for an account at query time
-- from hafbe_app.account_hbd_interest_cache and the median hbd_interest_rate
-- of the top-20 ranked witnesses.
--
-- Chain formula (from Hive: account_object::hbd_seconds):
--   hbd_seconds += hbd_balance * (now - hbd_seconds_last_update)
--   pending     = hbd_seconds / SECONDS_PER_YEAR * hbd_interest_rate / 10000
-- =============================================================================

SET ROLE hafbe_owner;

/*
 * account_pending_hbd_interest: Per-account HBD interest state.
 *
 * FIELDS:
 *   hbd_last_interest_payment - Timestamp of most recent liquid interest_operation,
 *                               or account creation time if never paid.
 *   hbd_seconds_last_update   - Timestamp of most recent liquid HBD balance change,
 *                               or hbd_last_interest_payment if balance never moved.
 *   hbd_seconds               - Accumulator: Σ(balance_i × Δt_i) since last payment,
 *                               not yet including the open interval up to head time.
 *                               Returned as TEXT (NUMERIC) — matches chain wire type.
 *   pending_hbd_interest      - HBD that would be paid right now if the 30-day gate
 *                               were open. In HBD asset units (BIGINT, 3 decimals).
 */
DROP TYPE IF EXISTS hafbe_backend.account_pending_hbd_interest CASCADE;
CREATE TYPE hafbe_backend.account_pending_hbd_interest AS (
    hbd_last_interest_payment TIMESTAMP,
    hbd_seconds_last_update   TIMESTAMP,
    hbd_seconds               TEXT,
    pending_hbd_interest      BIGINT
);

/*
 * get_chain_hbd_interest_rate: Chain-effective HBD interest rate (basis points).
 *
 * The chain rate is the median of the top-20 ranked witnesses' published rates,
 * which is what update_witness_props sets on the dynamic_global_property_object.
 * We approximate with PERCENTILE_CONT(0.5) over hafbe_app.current_witnesses
 * joined to hafbe_app.witness_rank_cache.
 *
 * RETURNS: INT in basis points (e.g. 2000 = 20%). Defaults to 0 if no witnesses
 *          have a populated rate yet.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.get_chain_hbd_interest_rate()
RETURNS INT
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN (
    SELECT COALESCE(
      PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY cw.hbd_interest_rate)::INT,
      0
    )
    FROM hafbe_app.current_witnesses cw
    JOIN hafbe_app.witness_rank_cache wrc ON wrc.witness_id = cw.witness_id
    WHERE wrc.rank <= 20
      AND cw.hbd_interest_rate IS NOT NULL
  );
END
$$;

/*
 * get_account_pending_hbd_interest: Compute pending liquid-HBD interest.
 *
 * APPROACH:
 *   1. Read the per-account accumulator maintained by
 *      hafbe_app.process_hbd_interest().
 *   2. Add the open trailing interval (last processed HBD balance update →
 *      HAFBE processed head time) using the cached liquid HBD balance.
 *   3. Apply the chain formula.
 *
 * EDGE CASES:
 *   - Never received liquid interest:     fall back to first balance change ts,
 *                                         or account creation if no history.
 *   - hbd_balance is 0:                   pending = 0 trivially.
 *   - hbd_interest_rate not yet computed: pending = 0 (no top-20 ranks yet).
 *
 * PARAMETERS:
 *   _account - Account ID
 *
 * RETURNS: account_pending_hbd_interest record
 */
CREATE OR REPLACE FUNCTION hafbe_backend.get_account_pending_hbd_interest(_account INT)
RETURNS hafbe_backend.account_pending_hbd_interest
LANGUAGE 'plpgsql' STABLE
AS
$$
DECLARE
  __SECONDS_PER_YEAR CONSTANT NUMERIC := 60 * 60 * 24 * 365;
  __HIVE_100_PERCENT CONSTANT NUMERIC := 10000;

  __interest_rate        INT := hafbe_backend.get_chain_hbd_interest_rate();
  __head_time            TIMESTAMP;
  __cache                RECORD;
  __account_created      TIMESTAMP;
  __hbd_seconds_for_calc NUMERIC := 0;
  __pending              BIGINT  := 0;
BEGIN
  SELECT bv.created_at INTO __head_time
  FROM hive.blocks_view bv
  WHERE bv.num = hafbe_backend.get_hafbe_head_block();

  __head_time := COALESCE(__head_time, hafbe_backend.default_timestamp());

  /*
   * The accumulator state is maintained by hafbe_app.process_hbd_interest()
   * (see db/process_hbd_interest.sql). One PK lookup replaces what was a
   * full balance-history walk + per-row hafd.operations join.
   *
   * Returned `hbd_seconds` is the chain-snapshot value (closed intervals
   * only, matching condenser_api.get_accounts). Pending interest, however,
   * extrapolates the open trailing interval up to head_time — same as the
   * chain's evaluate_hbd_interest() at payment time.
   */
  SELECT
    aic.hbd_seconds,
    aic.hbd_seconds_last_update,
    aic.last_balance,
    aic.hbd_last_interest_payment
  INTO __cache
  FROM hafbe_app.account_hbd_interest_cache aic
  WHERE aic.account = _account;

  IF NOT FOUND THEN
    SELECT ap.created INTO __account_created
    FROM hafbe_app.account_parameters ap
    WHERE ap.account = _account;

    __account_created := COALESCE(__account_created, hafbe_backend.default_timestamp());

    RETURN ROW(
      __account_created,
      __account_created,
      '0',
      0
    )::hafbe_backend.account_pending_hbd_interest;
  END IF;

  __hbd_seconds_for_calc :=
    __cache.hbd_seconds
    + __cache.last_balance::NUMERIC
      * EXTRACT(EPOCH FROM (__head_time - __cache.hbd_seconds_last_update));

  IF __interest_rate > 0 AND __hbd_seconds_for_calc > 0 THEN
    __pending := FLOOR(
      __hbd_seconds_for_calc / __SECONDS_PER_YEAR * __interest_rate::NUMERIC / __HIVE_100_PERCENT
    )::BIGINT;
  END IF;

  RETURN ROW(
    __cache.hbd_last_interest_payment,
    __cache.hbd_seconds_last_update,
    TRUNC(__cache.hbd_seconds)::TEXT,
    __pending
  )::hafbe_backend.account_pending_hbd_interest;
END
$$;

RESET ROLE;
