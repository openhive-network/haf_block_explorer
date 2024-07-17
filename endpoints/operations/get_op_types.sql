SET ROLE hafbe_owner;

/** openapi:paths
/operations/types:
  get:
    tags:
      - Operations
    summary: Lists operation types
    description: |
      Lists all types of operations available in the database

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_op_types();`
      
      * `SELECT * FROM hafbe_endpoints.get_op_types('comment');`

      REST call example
      * `GET https://{hafbe-host}/hafbe/operation-types`

      * `GET https://{hafbe-host}/hafbe/operation-types?input-value="comment"`
    operationId: hafbe_endpoints.get_op_types
    parameters:
      - in: query
        name: input-value
        required: false
        schema:
          type: string
          default: NULL
        description: parial name of operation
    responses:
      '200':
        description: |
          Operation type list, 
          if provided is `input-value` the list
          is limited to operations that partially match the `input-value`

          * Returns array of `hafbe_types.op_types`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hafbe_types.array_of_op_types'
            example:
              - op_type_id: 72
                operation_name: effective_comment_vote_operation
                is_virtual: true
              - op_type_id: 0
                operation_name: vote_operation
                is_virtual: false
      '404':
        description: No operations in the database
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_op_types;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_op_types(
    "input-value" TEXT = NULL
)
RETURNS SETOF hafbe_types.op_types 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
DECLARE
  __operation_name TEXT := NULL;
BEGIN

  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=31536000"}]', true);

  IF "input-value" IS NOT NULL THEN
    __operation_name := '%' || "input-value" || '%';
  END IF;  

  RETURN QUERY SELECT
    id::INT, split_part(name, '::', 3), is_virtual
  FROM hive.operation_types
  WHERE ((__operation_name IS NULL) OR (name LIKE __operation_name))
  ORDER BY id ASC
  ;

END
$$;

RESET ROLE;
