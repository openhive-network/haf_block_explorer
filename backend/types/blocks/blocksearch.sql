SET ROLE hafbe_owner;

/** openapi:components:schemas
hafbe_types.block_range:
  type: object
  properties:
    from:
      type: integer
    to:
      type: integer
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_types.block_range CASCADE;
CREATE TYPE hafbe_types.block_range AS (
    "from" INT,
    "to" INT
);
-- openapi-generated-code-end

/** openapi:components:schemas
hafbe_types.block_operations:
  type: object
  properties:
    op_type_id:
      type: integer
      description: operation type identifier
    op_count:
      type: integer
      description: amount of operations in block
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_types.block_operations CASCADE;
CREATE TYPE hafbe_types.block_operations AS (
    "op_type_id" INT,
    "op_count" INT
);
-- openapi-generated-code-end

/** openapi:components:schemas
hafbe_types.blocksearch:
  type: object
  properties:
    block_num:
      type: integer
      description: block number
    created_at:
      type: string
      format: date-time
      description: creation date
    producer_account:
      type: string
      description: account name of block''s producer
    producer_reward:
      type: string
      description: operation type identifier
    trx_count:
      type: integer
      description: count of transactions in block
    hash:
      type: string
      description: >-
        block hash in a blockchain is a unique, fixed-length string generated 
        by applying a cryptographic hash function to a block''s contents
    prev:
      type: string
      description: hash of a previous block
    operations:
      type: array
      items:
        $ref: '#/components/schemas/hafbe_types.block_operations'
      description: List of block_operation
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_types.blocksearch CASCADE;
CREATE TYPE hafbe_types.blocksearch AS (
    "block_num" INT,
    "created_at" TIMESTAMP,
    "producer_account" TEXT,
    "producer_reward" TEXT,
    "trx_count" INT,
    "hash" TEXT,
    "prev" TEXT,
    "operations" hafbe_types.block_operations[]
);
-- openapi-generated-code-end

/** openapi:components:schemas
hafbe_types.block_history:
  type: object
  properties:
    total_blocks:
      type: integer
      description: Total number of blocks
    total_pages:
      type: integer
      description: Total number of pages
    block_range:
      $ref: '#/components/schemas/hafbe_types.block_range'
      description: Range of blocks that contains the returned pages  
    blocks_result:
      type: array
      items:
        $ref: '#/components/schemas/hafbe_types.blocksearch'
      description: List of block results
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_types.block_history CASCADE;
CREATE TYPE hafbe_types.block_history AS (
    "total_blocks" INT,
    "total_pages" INT,
    "block_range" hafbe_types.block_range,
    "blocks_result" hafbe_types.blocksearch[]
);
-- openapi-generated-code-end

RESET ROLE;
