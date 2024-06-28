SET ROLE hafbe_owner;

/** openapi:paths
/operation-types/{input-value}:
  get:
    tags:
      - Operations
    summary: Lists operation types
    description: |
      Lists all types of operations that are matching with the `input-value`

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_matching_operation_types('comment');`

      * `SELECT * FROM hafbe_endpoints.get_matching_operation_types('vote');`
      
      REST call example
      * `GET https://{hafbe-host}/hafbe/operation-types/comment`
      
      * `GET https://{hafbe-host}/hafbe/operation-types/vote`
    operationId: hafbe_endpoints.get_matching_operation_types
    parameters:
      - in: path
        name: input-value
        required: true
        schema:
          type: string
        description: Given value
    responses:
      '200':
        description: |
          Operation type list

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
        description: No matching operations in the database
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_matching_operation_types;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_matching_operation_types(
    "input-value" TEXT
)
RETURNS SETOF hafbe_types.op_types 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
DECLARE
  __operation_name TEXT = '%' || "input-value" || '%';
BEGIN

PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=31536000"}]', true);

RETURN QUERY SELECT
  id::INT, split_part(name, '::', 3), is_virtual
FROM hive.operation_types
WHERE name LIKE __operation_name
ORDER BY id ASC
;

END
$$;

RESET ROLE;
