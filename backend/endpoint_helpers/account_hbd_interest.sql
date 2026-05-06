-- =============================================================================
-- Pending HBD Interest Helper
-- =============================================================================
-- Computes pending (unclaimed) HBD interest for an account at query time.
-- No new state — derives everything from btracker's account_balance_history
-- and the median hbd_interest_rate of the top-20 ranked witnesses.
--
-- Chain formula (from Hive: account_object::hbd_seconds):
--   hbd_seconds += hbd_balance * (now - hbd_seconds_last_update)
--   pending     = hbd_seconds / SECONDS_PER_YEAR * hbd_interest_rate / 10000
-- =============================================================================

SET ROLE hafbe_owner;

/*
 * account_pending_hbd_interest: Per-account HBD interest state, computed live.
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
 * APPROACH (no new state, all derived):
 *   1. Find timestamp of last liquid interest_operation paid to this account
 *      (rows in btracker_app.account_balance_history with nai=13 whose source_op
 *      is an interest_operation). This is hbd_last_interest_payment.
 *   2. Walk btracker_app.account_balance_history rows for (account, nai=13)
 *      from that timestamp to head, computing Σ(balance_i × Δt_i) where each
 *      Δt_i runs from the row's timestamp to the next row's timestamp.
 *   3. Add the open trailing interval (last row → head_time) using the current
 *      liquid HBD balance, then apply the chain formula.
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
  __HBD_NAI                CONSTANT SMALLINT := btracker_backend.nai_hbd();
  __SECONDS_PER_YEAR       CONSTANT NUMERIC  := 60 * 60 * 24 * 365;
  __HIVE_100_PERCENT       CONSTANT NUMERIC  := 10000;
  __op_interest            CONSTANT INT      := btracker_backend.op_interest();

  __interest_rate          INT := hafbe_backend.get_chain_hbd_interest_rate();
  __head_time              TIMESTAMP;
  __account_created        TIMESTAMP;
  __current_hbd_balance    BIGINT;
  __anchor_seq_no          INT;
  __last_interest_payment  TIMESTAMP;
  __hbd_seconds            NUMERIC := 0;
  __hbd_seconds_for_calc   NUMERIC := 0;
  __last_update            TIMESTAMP;
  __pending                BIGINT := 0;
BEGIN
  SELECT created_at INTO __head_time
  FROM hive.blocks_view
  ORDER BY num DESC
  LIMIT 1;

  SELECT ap.created INTO __account_created
  FROM hafbe_app.account_parameters ap
  WHERE ap.account = _account;

  -- btracker's schema is configurable (default btracker_app, here hafbe_bal),
  -- so reuse btracker_backend.current_account_balances_view which resolves it.
  SELECT cab.balance INTO __current_hbd_balance
  FROM btracker_backend.current_account_balances_view cab
  WHERE cab.account = _account
    AND cab.nai = __HBD_NAI;
  __current_hbd_balance := COALESCE(__current_hbd_balance, 0);

  /*
   * TIMESTAMP RULE: when a balance-changing op lands in block N, hived writes
   * `hbd_seconds_last_update = head_block_time()` inside adjust_balance(). The
   * value of head_block_time() depends on WHEN within block N's processing the
   * op fired, which is encoded in `operations.trx_in_block`:
   *
   *   trx_in_block >= 0  → fired DURING apply_transaction loop, before
   *                        update_global_dynamic_data. DGP.time is still
   *                        block N-1's timestamp → use source_op_block - 1.
   *
   *   trx_in_block = -1  → virtual op fired AFTER the apply_transaction loop
   *                        (process_comment_cashout, process_funds, etc.) and
   *                        after update_global_dynamic_data ran. DGP.time =
   *                        block N's timestamp → use source_op_block.
   *
   * (Reference: hive/libraries/chain/database.cpp:761, 2292-2829.)
   *
   * Anchor on balance_seq_no (not timestamp) so the walk below is a range scan
   * on idx_account_balance_history_account_seq_num_idx (account, nai, seq).
   *
   * Liquid (is_saved_into_hbd_balance=true) interest is the only kind that lands
   * in account_balance_history — savings interest goes to a separate table —
   * so source_op being an interest_operation uniquely identifies a liquid payout.
   */
  SELECT abh.balance_seq_no, bv.created_at
  INTO __anchor_seq_no, __last_interest_payment
  FROM btracker_backend.account_balance_history_view abh
  JOIN hafd.operations o   ON o.id  = abh.source_op
  JOIN hive.blocks_view bv ON bv.num = abh.source_op_block - CASE WHEN o.trx_in_block = -1 THEN 0 ELSE 1 END
  WHERE abh.account = _account
    AND abh.nai     = __HBD_NAI
    AND o.op_type_id = __op_interest
  ORDER BY abh.balance_seq_no DESC
  LIMIT 1;

  -- No liquid interest ever paid: anchor to first HBD activity, else account creation.
  IF __anchor_seq_no IS NULL THEN
    SELECT abh.balance_seq_no, bv.created_at
    INTO __anchor_seq_no, __last_interest_payment
    FROM btracker_backend.account_balance_history_view abh
    JOIN hafd.operations o   ON o.id  = abh.source_op
    JOIN hive.blocks_view bv ON bv.num = abh.source_op_block - CASE WHEN o.trx_in_block = -1 THEN 0 ELSE 1 END
    WHERE abh.account = _account
      AND abh.nai     = __HBD_NAI
    ORDER BY abh.balance_seq_no ASC
    LIMIT 1;
  END IF;

  __last_interest_payment := COALESCE(__last_interest_payment, __account_created, hafbe_backend.default_timestamp());

  -- No liquid HBD history at all: skip the walk and return zero state.
  IF __anchor_seq_no IS NULL THEN
    RETURN ROW(
      __last_interest_payment,
      __last_interest_payment,
      '0',
      0
    )::hafbe_backend.account_pending_hbd_interest;
  END IF;

  /*
   * Walk every (account, HBD) balance row from the anchor seq forward.
   *
   * Two-step pattern (consistent with proxies.sql, blocksearch_filters.sql):
   *   1. balance_rows MATERIALIZED — narrow to this account's HBD rows using
   *      the (account, nai, balance_seq_no) index before any joins.
   *   2. history — join hafd.operations and blocks_view only on the already-
   *      filtered set; trx_in_block drives the timestamp offset per the chain
   *      rule documented above.
   *
   * Each row holds running `balance` until the next row's timestamp:
   *   Δhbd_seconds_i = balance_i × (next_ts - this_ts).
   */
  WITH balance_rows AS MATERIALIZED (
    SELECT abh.balance, abh.source_op, abh.source_op_block, abh.balance_seq_no
    FROM btracker_backend.account_balance_history_view abh
    WHERE abh.account = _account
      AND abh.nai     = __HBD_NAI
      AND abh.balance_seq_no >= __anchor_seq_no
  ),
  history AS (
    SELECT
      br.balance,
      bv.created_at AS ts,
      LEAD(bv.created_at) OVER (ORDER BY br.balance_seq_no) AS next_ts
    FROM balance_rows br
    JOIN hafd.operations o   ON o.id  = br.source_op
    JOIN hive.blocks_view bv ON bv.num = br.source_op_block - CASE WHEN o.trx_in_block = -1 THEN 0 ELSE 1 END
  )
  SELECT
    -- Chain-snapshot semantic: only sum CLOSED intervals (next_ts IS NOT NULL).
    -- The last row's next_ts is NULL → its term is NULL → SUM ignores it. This
    -- matches what hived stores in account_object.hbd_seconds at last_update.
    COALESCE(SUM(
      h.balance::NUMERIC
      * EXTRACT(EPOCH FROM (h.next_ts - h.ts))
    ), 0),
    MAX(h.ts)
  INTO __hbd_seconds, __last_update
  FROM history h;

  __last_update := COALESCE(__last_update, __last_interest_payment);

  /*
   * pending = (hbd_seconds + balance × (now − last_update)) / SECONDS_PER_YEAR
   *           × rate / 10000
   *
   * The chain extrapolates the open trailing interval inside evaluate_hbd_interest()
   * at payment time; we replicate that arithmetic for the API but keep the
   * `hbd_seconds` field itself as the chain-snapshot value so it matches
   * condenser_api.get_accounts.
   */
  __hbd_seconds_for_calc :=
    __hbd_seconds
    + __current_hbd_balance::NUMERIC
      * EXTRACT(EPOCH FROM (__head_time - __last_update));

  IF __interest_rate > 0 AND __hbd_seconds_for_calc > 0 THEN
    __pending := FLOOR(
      __hbd_seconds_for_calc / __SECONDS_PER_YEAR * __interest_rate::NUMERIC / __HIVE_100_PERCENT
    )::BIGINT;
  END IF;

  RETURN ROW(
    __last_interest_payment,
    __last_update,
    TRUNC(__hbd_seconds)::TEXT,
    __pending
  )::hafbe_backend.account_pending_hbd_interest;
END
$$;

RESET ROLE;
