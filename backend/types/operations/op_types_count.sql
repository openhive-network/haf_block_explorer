/** openapi:components:schemas
hafbe_types.op_types_count:
  type: object
  properties:
    op_type_id:
      type: integer
      description: operation type id
    count:
      type: integer
      x-sql-datatype: BIGINT
      description: number of operations in the block
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_types.op_types_count CASCADE;
CREATE TYPE hafbe_types.op_types_count AS (
    "op_type_id" INT,
    "count" BIGINT
);
-- openapi-generated-code-end

/** openapi:components:schemas
hafbe_types.array_of_op_types_count:
  type: array
  items:
    $ref: '#/components/schemas/hafbe_types.op_types_count'
*/
