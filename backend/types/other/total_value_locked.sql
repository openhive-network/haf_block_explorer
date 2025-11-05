SET ROLE hafbe_owner;

/** openapi:components:schemas
hafbe_types.total_value_locked:
  type: object
  properties:
    block_num:
      type: integer
      description: Head block number at which the snapshot was computed
    total_vests:
      type: integer
      x-sql-datatype: BIGINT
      description: Global sum of VESTS from hafbe_bal.current_account_balances (nai=37)
    savings_hive:
      type: integer
      x-sql-datatype: BIGINT
      description: Total number of HIVE in savings from hafbe_bal.account_savings (nai=21)
    savings_hbd:
      type: integer
      x-sql-datatype: BIGINT
      description: Total number of HIVE backed dollars the chain has in savings (hafbe_bal.account_savings nai=13)
*/
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_types.total_value_locked CASCADE;
CREATE TYPE hafbe_types.total_value_locked AS (
    "block_num" INT,
    "total_vests" BIGINT,
    "savings_hive" BIGINT,
    "savings_hbd" BIGINT
);
-- openapi-generated-code-end

RESET ROLE;
