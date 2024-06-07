SET ROLE hafbe_owner;

/** openapi:components:schemas
hafbe_types.block_by_ops:
  type: object
  properties:
    block_num:
      type: integer
      description: block number
    op_type_id:
      type: array
      items:
        type: integer
      x-sql-datatype: INT[]
      description: list of operation types
*/
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_types.block_by_ops CASCADE;
CREATE TYPE hafbe_types.block_by_ops AS (
    "block_num" INT,
    "op_type_id" INT[]
);
-- openapi-generated-code-end

/** openapi:components:schemas
hafbe_types.array_of_block_by_ops:
  type: array
  items:
    $ref: '#/components/schemas/hafbe_types.block_by_ops'
*/

RESET ROLE;
