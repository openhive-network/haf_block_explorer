SET ROLE hafbe_owner;

/** openapi:components:schemas
hafbe_types.comment_history:
  type: object
  properties:
    permlink:
      type: string
      description: >-
        unique post identifier containing post's title and generated number
    block_num:
      type: integer
      description: operation block number
    operation_id:
      type: integer
      x-sql-datatype: BIGINT
      description: >-
        unique operation identifier with
        an encoded block number and operation type id
    created_at:
      type: string
      format: date-time
      description: creation date
    trx_hash:
      type: string
      description: hash of the transaction
    operation:
      type: string
      x-sql-datatype: JSONB
      description: operation body
    is_modified:
      type: boolean
      description: >-
        true if operation body was modified with body placeholder due to its lenght
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_types.comment_history CASCADE;
CREATE TYPE hafbe_types.comment_history AS (
    "permlink" TEXT,
    "block_num" INT,
    "operation_id" BIGINT,
    "created_at" TIMESTAMP,
    "trx_hash" TEXT,
    "operation" JSONB,
    "is_modified" BOOLEAN
);
-- openapi-generated-code-end

RESET ROLE;