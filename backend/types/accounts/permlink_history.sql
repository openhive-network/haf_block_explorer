SET ROLE hafbe_owner;

/** openapi:components:schemas
hafbe_types.permlink_history:
  type: object
  properties:
    permlink:
      type: string
      description: >-
        unique post identifier containing post''s title and generated number
    block:
      type: integer
      description: operation block number
    trx_id:
      type: string
      description: hash of the transaction
    timestamp:
      type: string
      format: date-time
      description: creation date
    operation_id:
      type: integer
      x-sql-datatype: TEXT
      description: >-
        unique operation identifier with
        an encoded block number and operation type id
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_types.permlink_history CASCADE;
CREATE TYPE hafbe_types.permlink_history AS (
    "permlink" TEXT,
    "block" INT,
    "trx_id" TEXT,
    "timestamp" TIMESTAMP,
    "operation_id" TEXT
);
-- openapi-generated-code-end



RESET ROLE;
