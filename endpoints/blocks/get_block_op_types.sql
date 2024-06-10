SET ROLE hafbe_owner;

/** openapi:paths
/hafbe/blocks/{block-num}/operations/types:
  get:
    tags:
      - Blocks
    summary:  List operations that were present in given block
    description: |
      List operations that were present in given block

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_block_op_types(10000);`

      * `SELECT * FROM hafbe_endpoints.get_block_op_types(43000);`
      
      REST call example
      * `GET https://{hafbe-host}/hafbe/blocks/10000/operations/types`
      
      * `GET https://{hafbe-host}/hafbe/blocks/43000/operations/types`
    operationId: hafbe_endpoints.get_block_op_types
    parameters:
      - in: path
        name: block-num
        required: true
        schema:
          type: integer
        description: Given block number
    responses:
      '200':
        description: |
          Given block's operation list

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
        description: No block in the database
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_block_op_types;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_block_op_types(
    "block-num" INT
)
RETURNS SETOF hafbe_types.op_types 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
SET JIT = OFF
SET join_collapse_limit = 16
SET from_collapse_limit = 16
AS
$$
BEGIN

IF "block-num" <= hive.app_get_irreversible_block() THEN
  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=31536000"}]', true);
ELSE
  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);
END IF;

RETURN QUERY SELECT DISTINCT ON (ov.op_type_id)
  ov.op_type_id, split_part( hot.name, '::', 3), hot.is_virtual
FROM hive.operations_view ov
JOIN hive.operation_types hot ON hot.id = ov.op_type_id
WHERE ov.block_num = "block-num"
ORDER BY ov.op_type_id ASC
;

END
$$;

RESET ROLE;
