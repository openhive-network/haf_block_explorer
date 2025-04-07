SET ROLE hafbe_owner;

/** openapi:components:schemas
hafbe_types.latest_blocks:
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
        $ref: '#/components/schemas/hafbe_types.block_operations'
      description: List of block_operation
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_types.latest_blocks CASCADE;
CREATE TYPE hafbe_types.latest_blocks AS (
    "block_num" INT,
    "witness" TEXT,
    "operations" hafbe_types.block_operations[]
);
-- openapi-generated-code-end


/** openapi:components:schemas
hafbe_types.array_of_latest_blocks:
  type: array
  items:
    $ref: '#/components/schemas/hafbe_types.latest_blocks'
*/

RESET ROLE;
