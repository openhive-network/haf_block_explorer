SET ROLE hafbe_owner;

/** openapi:components:schemas
hafbe_types.input_type_return:
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
DROP TYPE IF EXISTS hafbe_types.input_type_return CASCADE;
CREATE TYPE hafbe_types.input_type_return AS (
    "input_type" TEXT,
    "input_value" TEXT[]
);
-- openapi-generated-code-end

RESET ROLE;
