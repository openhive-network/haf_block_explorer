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
    ops_count:
      type: string
      x-sql-datatype: JSON
      description: count of each operation type
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_types.latest_blocks CASCADE;
CREATE TYPE hafbe_types.latest_blocks AS (
    "block_num" INT,
    "witness" TEXT,
    "ops_count" JSON
);
-- openapi-generated-code-end


/** openapi:components:schemas
hafbe_types.array_of_latest_blocks:
  type: array
  items:
    $ref: '#/components/schemas/hafbe_types.latest_blocks'
*/

RESET ROLE;
