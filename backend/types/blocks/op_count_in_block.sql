SET ROLE hafbe_owner;

/** openapi:components:schemas
hafbe_types.op_count_in_block:
  type: object
  properties:
    op_type_id:
      type: integer
      description: operation id
    count:
      type: integer
      x-sql-datatype: BIGINT
      description: number of the operations in block
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_types.op_count_in_block CASCADE;
CREATE TYPE hafbe_types.op_count_in_block AS (
    "op_type_id" INT,
    "count" BIGINT
);
-- openapi-generated-code-end


/** openapi:components:schemas
hafbe_types.array_of_op_count_in_block:
  type: array
  items:
    $ref: '#/components/schemas/hafbe_types.op_count_in_block'
*/

RESET ROLE;
