SET ROLE hafbe_owner;

/** openapi:components:schemas
hafbe_types.operation:
  type: object
  properties:
    operation_id:
      type: string
      description: >-
        unique operation identifier with
        an encoded block number and operation type id
    block_num:
      type: integer
      description: operation block number
    trx_in_block:
      type: integer
      x-sql-datatype: SMALLINT
      description: >-
        transaction identifier that indicates its sequence number in block
    trx_id:
      type: string
      description: hash of the transaction
    op_pos:
      type: integer
      description: >-
        operation identifier that indicates its sequence number in transaction
    op_type_id:
      type: integer
      description: operation type identifier
    operation:
      type: string
      x-sql-datatype: JSONB
      description: operation body
    virtual_op:
      type: boolean
      description: true if is a virtual operation
    timestamp:
      type: string
      format: date-time
      description: creation date
    age:
      type: string
      x-sql-datatype: INTERVAL
      description: how old is the operation
    is_modified:
      type: boolean
      description: >-
        true if operation body was modified with body placeholder due to its lenght
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_types.operation CASCADE;
CREATE TYPE hafbe_types.operation AS (
    "operation_id" TEXT,
    "block_num" INT,
    "trx_in_block" SMALLINT,
    "trx_id" TEXT,
    "op_pos" INT,
    "op_type_id" INT,
    "operation" JSONB,
    "virtual_op" BOOLEAN,
    "timestamp" TIMESTAMP,
    "age" INTERVAL,
    "is_modified" BOOLEAN
);
-- openapi-generated-code-end

RESET ROLE;
