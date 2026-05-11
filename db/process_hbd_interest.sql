SET ROLE hafbe_owner;

/*
 * process_hbd_interest: Maintains hafbe_app.account_hbd_interest_cache for
 * every HBD-affecting balance change in the operation range [_from, _to].
 *
 * STATE PER ACCOUNT (one row, mutated in place):
 *   hbd_seconds               - Σ(balance_i × Δt_i) since last interest payment
 *   hbd_seconds_last_update   - Timestamp of most recent HBD balance-changing op
 *   last_balance              - Liquid HBD balance immediately after that op
 *   hbd_last_interest_payment - Timestamp of most recent interest_operation
 *
 * BULK ALGORITHM:
 *   Per account in the range, each row's contribution to hbd_seconds is
 *   prev_balance × (this_ts - prev_ts), where prev_balance/prev_ts are the
 *   previous row in the range (LAG window) or the cache's prior state for the
 *   first row. interest_operations reset hbd_seconds to 0, so the running
 *   total only counts deltas AFTER the latest interest_op (if any). The whole
 *   computation collapses to one INSERT .. ON CONFLICT DO UPDATE.
 *
 * TIMESTAMP RULE:
 *   trx_in_block >= 0 -> blocks_view(source_op_block - 1).created_at
 *   trx_in_block = -1 -> blocks_view(source_op_block).created_at
 *
 * The id-range predicate on hafd.operations enables TimescaleDB chunk
 * exclusion on the compressed hypertable.
 */
CREATE OR REPLACE FUNCTION hafbe_app.process_hbd_interest(_from INT, _to INT)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
AS
$$
DECLARE
  __HBD_NAI     CONSTANT SMALLINT := btracker_backend.nai_hbd();
  __op_interest CONSTANT INT      := btracker_backend.op_interest();
BEGIN
  WITH
  /*
   * Narrow btracker history to HBD rows in this block range first, then join
   * hafd.operations for the exact trx_in_block timestamp correction and
   * interest_operation detection.
   */
  ops_in_range AS MATERIALIZED (
    SELECT
      abh.account,
      abh.balance,
      abh.balance_seq_no,
      abh.source_op,
      (o.op_type_id = __op_interest) AS is_interest_op,
      bv.created_at              AS ts
    FROM btracker_backend.account_balance_history_view abh
    JOIN hafd.operations o
      ON o.id = abh.source_op
     AND o.id >= hafd.operation_id(_from, 0)
     AND o.id <  hafd.operation_id(_to + 1, 0)
    JOIN hive.blocks_view bv
      ON bv.num = abh.source_op_block - CASE WHEN o.trx_in_block = -1 THEN 0 ELSE 1 END
    WHERE abh.nai = __HBD_NAI
      AND abh.source_op >= hafd.operation_id(_from, 0)
      AND abh.source_op <  hafd.operation_id(_to + 1, 0)
  ),
  /*
   * For each row attach the cache's prior state (if any) and the next row's
   * timestamp. This mirrors the old endpoint calculation: each row's balance
   * accrues until the next balance-history row.
   */
  ops_with_state AS (
    SELECT
      o.account,
      o.balance,
      o.balance_seq_no,
      o.source_op,
      o.is_interest_op,
      o.ts,
      LEAD(o.ts) OVER w AS next_ts_in_range,
      COALESCE(c.last_balance, 0)                  AS init_balance,
      COALESCE(c.hbd_seconds_last_update, o.ts)    AS init_ts,
      COALESCE(c.hbd_seconds, 0)                   AS init_hbd_seconds,
      COALESCE(c.hbd_last_interest_payment, o.ts)  AS init_payment,
      ROW_NUMBER() OVER w AS rn
    FROM ops_in_range o
    LEFT JOIN hafbe_app.account_hbd_interest_cache c ON c.account = o.account
    WINDOW w AS (PARTITION BY o.account ORDER BY o.balance_seq_no)
  ),
  /*
   * Per-row closed interval. The last row has no next_ts in this batch, so its
   * open interval is intentionally not included in hbd_seconds. It is added by
   * the endpoint when calculating pending interest.
   */
  ops_with_delta AS (
    SELECT
      o.*,
      o.balance::NUMERIC * EXTRACT(EPOCH FROM (next_ts_in_range - ts)) AS delta_hbd_seconds,
      CASE
        WHEN rn = 1 THEN init_balance::NUMERIC * EXTRACT(EPOCH FROM (ts - init_ts))
        ELSE 0
      END AS init_delta_hbd_seconds
    FROM ops_with_state o
  ),
  /*
   * Per account, the balance_seq_no of the latest interest_operation in the range
   * (NULL if none). hbd_seconds resets at every interest_op, so only deltas
   * from the latest interest row contribute to the final value.
   */
  acc_latest_interest AS (
    SELECT account, MAX(balance_seq_no) AS latest_interest_seq_no
    FROM ops_with_delta
    WHERE is_interest_op
    GROUP BY account
  ),
  /*
   * Collapse per-account ops into the final cache row.
   *
   *   new_hbd_seconds:
   *     - if latest_interest_seq_no IS NOT NULL: Σ(closed intervals) from
   *       the interest row forward
   *     - else: init_hbd_seconds + initial cache interval + all closed intervals
   *
   *   new_last_balance / new_last_update: from the last balance_seq_no
   *   new_last_payment: latest interest_op ts in range, else cache's prior value
   */
  per_account_final AS (
    SELECT
      o.account,
      (array_agg(o.balance ORDER BY o.balance_seq_no DESC))[1] AS new_last_balance,
      (array_agg(o.ts      ORDER BY o.balance_seq_no DESC))[1] AS new_last_update,
      CASE
        WHEN ali.latest_interest_seq_no IS NOT NULL THEN
          COALESCE(SUM(o.delta_hbd_seconds) FILTER (WHERE o.balance_seq_no >= ali.latest_interest_seq_no), 0)
        ELSE
          MAX(o.init_hbd_seconds)
          + COALESCE(MAX(o.init_delta_hbd_seconds) FILTER (WHERE o.rn = 1), 0)
          + COALESCE(SUM(o.delta_hbd_seconds), 0)
      END AS new_hbd_seconds,
      COALESCE(
        (array_agg(o.ts ORDER BY o.balance_seq_no DESC) FILTER (WHERE o.is_interest_op))[1],
        MAX(o.init_payment)
      ) AS new_last_payment
    FROM ops_with_delta o
    LEFT JOIN acc_latest_interest ali ON ali.account = o.account
    GROUP BY o.account, ali.latest_interest_seq_no
  )
  INSERT INTO hafbe_app.account_hbd_interest_cache (
    account, hbd_seconds, hbd_seconds_last_update, last_balance, hbd_last_interest_payment
  )
  SELECT
    account, new_hbd_seconds, new_last_update, new_last_balance, new_last_payment
  FROM per_account_final
  ON CONFLICT (account) DO UPDATE SET
    hbd_seconds               = EXCLUDED.hbd_seconds,
    hbd_seconds_last_update   = EXCLUDED.hbd_seconds_last_update,
    last_balance              = EXCLUDED.last_balance,
    hbd_last_interest_payment = EXCLUDED.hbd_last_interest_payment;
END
$$;

RESET ROLE;
