SET ROLE hafbe_owner;

/** openapi:paths
/hafbe/operation-types:
  get:
    tags:
      - Operations
    summary: Lists operation types
    description: |
      Lists all types of operations available in the database

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_op_types();`
      
      REST call example
      * `GET https://{hafbe-host}/hafbe/operation-types`
    operationId: hafbe_endpoints.get_op_types
    parameters:
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
        description: No operations in the database
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_op_types;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_op_types()
RETURNS SETOF hafbe_types.op_types 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN

PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=31536000"}]', true);

RETURN QUERY SELECT
  id::INT, split_part(name, '::', 3), is_virtual
FROM hive.operation_types
ORDER BY id ASC
;

END
$$;

RESET ROLE;
