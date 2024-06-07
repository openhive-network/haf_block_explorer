SET ROLE hafbe_owner;

/** openapi:components:schemas
hafbe_types.op_types:
  type: object
  properties:
    op_type_id:
      type: integer
      description: operation type id
    operation_name:
      type: string
      description: operation type name
    is_virtual:
      type: boolean
      description: true if operation is virtual
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_types.op_types CASCADE;
CREATE TYPE hafbe_types.op_types AS (
    "op_type_id" INT,
    "operation_name" TEXT,
    "is_virtual" BOOLEAN
);
-- openapi-generated-code-end

/** openapi:components:schemas
hafbe_types.array_of_op_types:
  type: array
  items:
    $ref: '#/components/schemas/hafbe_types.op_types'
*/

RESET ROLE;
