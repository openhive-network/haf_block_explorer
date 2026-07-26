SET ROLE hafbe_owner;

-- Block-related types for hafbe_backend

----------------------------------------------------------------------

/** openapi:components:schemas
hafbe_backend.block_range:
  type: object
  properties:
    from:
      type: integer
    to:
      type: integer
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.block_range CASCADE;
CREATE TYPE hafbe_backend.block_range AS (
    "from" INT,
    "to" INT
);
-- openapi-generated-code-end

----------------------------------------------------------------------

/** openapi:components:schemas
hafbe_backend.block_operations:
  type: object
  properties:
    op_type_id:
      type: integer
      description: operation type identifier
    op_count:
      type: integer
      description: amount of operations in block
 */
-- WARNING: hafbe_backend.block_operations is the ROOT of the block-search type chain:
--   block_operations -> gathered_block.operations[] -> gatherer_result.blocks[]
--     -> the eight blocksearch_* gatherers (backend/endpoint_helpers/blocksearch_filters.sql)
--     -> blocksearch_build_result (backend/utilities/blocksearch.sql)
-- The CASCADE below therefore destroys ALL of the above, none of which are defined in this
-- file. A full install_app.sh run re-creates them afterwards (backend/types/blocksearch.sql,
-- then blocksearch.sql, then blocksearch_filters.sql, then endpoint_helpers/blocks.sql) and
-- self-heals; applying THIS FILE ALONE leaves /block-search answering HTTP 500 on every
-- variant. If you hot-patch it, re-apply those four files too -- or just re-run setup_api,
-- whose verify_api_surface check exists to catch exactly this.
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.block_operations CASCADE;
CREATE TYPE hafbe_backend.block_operations AS (
    "op_type_id" INT,
    "op_count" INT
);
-- openapi-generated-code-end

----------------------------------------------------------------------

/** openapi:components:schemas
hafbe_backend.blocksearch:
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
        $ref: '#/components/schemas/hafbe_backend.block_operations'
      description: List of block_operation
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.blocksearch CASCADE;
CREATE TYPE hafbe_backend.blocksearch AS (
    "block_num" INT,
    "created_at" TIMESTAMP,
    "producer_account" TEXT,
    "producer_reward" TEXT,
    "trx_count" INT,
    "hash" TEXT,
    "prev" TEXT,
    "operations" hafbe_backend.block_operations[]
);
-- openapi-generated-code-end

----------------------------------------------------------------------

/** openapi:components:schemas
hafbe_backend.block_history:
  type: object
  properties:
    total_blocks:
      type: integer
      description: Total number of blocks
    total_pages:
      type: integer
      description: Total number of pages
    block_range:
      $ref: '#/components/schemas/hafbe_backend.block_range'
      description: Range of blocks that contains the returned pages
    blocks_result:
      type: array
      items:
        $ref: '#/components/schemas/hafbe_backend.blocksearch'
      description: List of block results
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.block_history CASCADE;
CREATE TYPE hafbe_backend.block_history AS (
    "total_blocks" INT,
    "total_pages" INT,
    "block_range" hafbe_backend.block_range,
    "blocks_result" hafbe_backend.blocksearch[]
);
-- openapi-generated-code-end

----------------------------------------------------------------------

/** openapi:components:schemas
hafbe_backend.latest_blocks:
  type: object
  properties:
    block_num:
      type: integer
      description: block number
    witness:
      type: string
      description: witness that created the block
    operations:
      type: array
      items:
        $ref: '#/components/schemas/hafbe_backend.block_operations'
      description: List of block_operation
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.latest_blocks CASCADE;
CREATE TYPE hafbe_backend.latest_blocks AS (
    "block_num" INT,
    "witness" TEXT,
    "operations" hafbe_backend.block_operations[]
);
-- openapi-generated-code-end


/** openapi:components:schemas
hafbe_backend.array_of_latest_blocks:
  type: array
  items:
    $ref: '#/components/schemas/hafbe_backend.latest_blocks'
*/

----------------------------------------------------------------------

/** openapi:components:schemas
hafbe_backend.input_type_return:
  type: object
  properties:
    input_type:
      type: string
      description: operation type id
    input_value:
      type: array
      items:
        type: string
      description: number of operations in the block
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.input_type_return CASCADE;
CREATE TYPE hafbe_backend.input_type_return AS (
    "input_type" TEXT,
    "input_value" TEXT[]
);
-- openapi-generated-code-end

RESET ROLE;
