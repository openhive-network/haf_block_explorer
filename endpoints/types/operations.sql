SET ROLE hafbe_owner;

-- Operation-related types for hafbe_backend

----------------------------------------------------------------------

/** openapi:components:schemas
hafbe_backend.operation_body:
  type: object
  x-sql-datatype: JSON
  properties:
    type:
      type: string
    value:
      type: object
*/

/** openapi:components:schemas
hafbe_backend.operation:
  type: object
  properties:
    op:
      $ref: '#/components/schemas/hafah_backend.operation_body'
      x-sql-datatype: JSONB
      description: operation body
    block:
      type: integer
      description: operation block number
    trx_id:
      type: string
      description: hash of the transaction
    op_pos:
      type: integer
      description: >-
        operation identifier that indicates its sequence number in transaction
    op_type_id:
      type: integer
      x-sql-datatype: SMALLINT
      description: operation type identifier
    timestamp:
      type: string
      format: date-time
      description: the time operation was included in the blockchain
    virtual_op:
      type: boolean
      description: true if is a virtual operation
    operation_id:
      type: string
      description: >-
        unique operation identifier with
        an encoded block number and operation type id
    trx_in_block:
      type: integer
      x-sql-datatype: SMALLINT
      description: >-
        transaction identifier that indicates its sequence number in block
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.operation CASCADE;
CREATE TYPE hafbe_backend.operation AS (
    "op" JSONB,
    "block" INT,
    "trx_id" TEXT,
    "op_pos" INT,
    "op_type_id" SMALLINT,
    "timestamp" TIMESTAMP,
    "virtual_op" BOOLEAN,
    "operation_id" TEXT,
    "trx_in_block" SMALLINT
);
-- openapi-generated-code-end

----------------------------------------------------------------------

/** openapi:components:schemas
hafbe_backend.operation_history:
  type: object
  properties:
    total_operations:
      type: integer
      description: Total number of operations
    total_pages:
      type: integer
      description: Total number of pages
    operations_result:
      type: array
      items:
        $ref: '#/components/schemas/hafbe_backend.operation'
      description: List of operation results
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.operation_history CASCADE;
CREATE TYPE hafbe_backend.operation_history AS (
    "total_operations" INT,
    "total_pages" INT,
    "operations_result" hafbe_backend.operation[]
);
-- openapi-generated-code-end

RESET ROLE;
