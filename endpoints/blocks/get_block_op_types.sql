SET ROLE hafbe_owner;

/** openapi:paths
/blocks/{block-num}/operation-types/count:
  get:
    tags:
      - Blocks
    summary:  List operations that were present in given block
    description: |
      List operations that were present in given block

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_block_op_types(5000000);`
      
      REST call example   
      * `GET ''https://%1$s/hafbe/blocks/5000000/operation-types/count''`
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
          Operation counts for a given block-num

          * Returns array of `hafbe_types.op_types_count`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hafbe_types.array_of_op_types_count'
            example:
              - op_type_id: 80
                count: 1
              - op_type_id: 9
                count: 1
              - op_type_id: 5
                count: 1
              - op_type_id: 64
                count: 1
      '404':
        description: No block in the database
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_block_op_types;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_block_op_types(
    "block-num" INT
)
RETURNS SETOF hafbe_types.op_types_count 
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

  RETURN QUERY (
    SELECT 
      ov.op_type_id,
      COUNT(ov.op_type_id) as count 
    FROM hive.operations_view ov
    WHERE ov.block_num = "block-num"
    GROUP BY ov.op_type_id
  );
END
$$;

RESET ROLE;
