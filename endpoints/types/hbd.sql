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
      type: integer
      format: int64
      x-sql-datatype: BIGINT
      description: Total HBD supply in milli-HBD, including the treasury.
    virtual_supply:
      type: integer
      format: int64
      x-sql-datatype: BIGINT
      description: Virtual supply in milli-HIVE.
    debt_ratio_pct:
      type: [number, 'null']
      x-sql-datatype: NUMERIC
      description: >-
        Provisional formula from issue 147: 100 * current_hbd_supply / virtual_supply.
        The supplies have different asset units; this is not the protocol debt ratio.
        The definition is pending clarification. Null when virtual_supply is zero.
    hbd_interest_rate:
      type: integer
      description: Declared HBD interest rate in basis points; 1500 means 15%%.
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.hbd_status CASCADE;
CREATE TYPE hafbe_backend.hbd_status AS (
    "period" TIMESTAMP,
    "hbd_supply" BIGINT,
    "virtual_supply" BIGINT,
    "debt_ratio_pct" NUMERIC,
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
