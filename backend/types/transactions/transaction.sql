SET ROLE hafbe_owner;

/** openapi:components:schemas
hafbe_types.transaction:
  type: object
  properties:
    transaction_json:
      type: string
      x-sql-datatype: JSON
      description: contents of the transaction
    transaction_id:
      type: string
      description: hash of the transaction
    block_num:
      type: integer
      description: number of block the transaction was in
    transaction_num:
      type: integer
      description: number of the transaction in block
    timestamp:
      type: string
      format: date-time
      description: the time of the transaction was made
    age:
      type: string
      x-sql-datatype: INTERVAL
      description: how old is the transaction
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_types.transaction CASCADE;
CREATE TYPE hafbe_types.transaction AS (
    "transaction_json" JSON,
    "transaction_id" TEXT,
    "block_num" INT,
    "transaction_num" INT,
    "timestamp" TIMESTAMP,
    "age" INTERVAL
);
-- openapi-generated-code-end

RESET ROLE;
