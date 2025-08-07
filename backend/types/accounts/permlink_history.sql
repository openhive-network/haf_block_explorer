SET ROLE hafbe_owner;

/** openapi:components:schemas
hafbe_types.permlink:
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
      type: string
      description: >-
        unique operation identifier with
        an encoded block number and operation type id
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_types.permlink CASCADE;
CREATE TYPE hafbe_types.permlink AS (
    "permlink" TEXT,
    "block" INT,
    "trx_id" TEXT,
    "timestamp" TIMESTAMP,
    "operation_id" TEXT
);
-- openapi-generated-code-end

/** openapi:components:schemas
hafbe_types.permlink_history:
  type: object
  properties:
    total_permlinks:
      type: integer
      description: Total number of permlinks
    total_pages:
      type: integer
      description: Total number of pages
    block_range:
      $ref: '#/components/schemas/hafbe_types.block_range'
      description: Range of blocks that contains the returned pages  
    permlinks_result:
      type: array
      items:
        $ref: '#/components/schemas/hafbe_types.permlink'
      description: List of permlinks
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_types.permlink_history CASCADE;
CREATE TYPE hafbe_types.permlink_history AS (
    "total_permlinks" INT,
    "total_pages" INT,
    "block_range" hafbe_types.block_range,
    "permlinks_result" hafbe_types.permlink[]
);
-- openapi-generated-code-end


RESET ROLE;
