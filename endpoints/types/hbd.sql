SET ROLE hafbe_owner;

/** openapi:components:schemas
hafbe_backend.hbd_granularity:
  type: string
  enum:
    - daily
    - weekly
    - monthly
    - yearly
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.hbd_granularity CASCADE;
CREATE TYPE hafbe_backend.hbd_granularity AS ENUM (
    'daily',
    'weekly',
    'monthly',
    'yearly'
);
-- openapi-generated-code-end

/** openapi:components:schemas
hafbe_backend.hbd_status:
  type: object
  properties:
    period:
      type: string
      format: date-time
      description: >-
        End of the UTC period, capped at the current time, as in transaction statistics.
        Values come from the last processed block of the period, which may be earlier than this label.
    hbd_supply:
      type: string
      description: Total HBD supply in milli-HBD, including the treasury, as a string to preserve integer precision.
    hive_supply:
      type: string
      description: HIVE supply in milli-HIVE at the sampled block, as a string to preserve integer precision.
    virtual_supply:
      type: string
      description: Virtual supply in milli-HIVE as a string to preserve integer precision.
    debt_ratio_gross_pct:
      type: [number, 'null']
      x-sql-datatype: NUMERIC
      description: >-
        Gross HBD value share of virtual supply: 100 * (virtual_supply - hive_supply) / virtual_supply.
        Uses the effective median price, including any hard-cap adjustment.
        Equals the protocol debt ratio before HF24; from HF24 the protocol excludes treasury HBD
        while this gross series includes it. From HF24 the print-rate thresholds apply to
        debt_ratio_protocol_pct instead; the hard cap still follows this gross series until HF25.
        Rounded to three decimal places.
        Null when virtual_supply is zero.
    debt_ratio_protocol_pct:
      type: [number, 'null']
      x-sql-datatype: NUMERIC
      description: >-
        HBD debt ratio as the protocol computes it (hived calculate_HBD_percent), from the state after the
        sampled block. From HF24 the treasury''s (hive.fund) liquid HBD is left out of the HBD supply and the
        rest is valued at the same price: with p = (virtual_supply - hive_supply) / hbd_supply and
        h = max(hbd_supply - treasury_hbd, 0), it is 100 * h * p / (h * p + hive_supply), and 0 when h is 0.
        Before HF24 it equals debt_ratio_gross_pct.
        The print-rate thresholds apply to this series (from HF14; from HF24 with the treasury left out).
        The hard cap applies to it from HF25; between HF24 and HF25 the chain capped on the gross share.
        Rounded to three decimal places. hived computes basis points during block processing, slightly
        before the end-of-block state used here, so the two can differ by about its 0.01%% step.
        Null when virtual_supply is zero.
    hbd_interest_rate:
      type: integer
      description: Declared HBD interest rate in basis points; 1500 means 15%%.
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.hbd_status CASCADE;
CREATE TYPE hafbe_backend.hbd_status AS (
    "period" TIMESTAMP,
    "hbd_supply" TEXT,
    "hive_supply" TEXT,
    "virtual_supply" TEXT,
    "debt_ratio_gross_pct" NUMERIC,
    "debt_ratio_protocol_pct" NUMERIC,
    "hbd_interest_rate" INT
);
-- openapi-generated-code-end

/** openapi:components:schemas
hafbe_backend.array_of_hbd_status:
  type: array
  items:
    $ref: '#/components/schemas/hafbe_backend.hbd_status'
 */

RESET ROLE;
