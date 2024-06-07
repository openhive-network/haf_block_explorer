SET ROLE hafbe_owner;

/** openapi:paths
/hafbe/blocks/{block-num}/operations-count:
  get:
    tags:
      - Blocks
    summary: Count operations in block
    description: |
      List count for each operation type for given block number

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_op_count_in_block(10000);`

      * `SELECT * FROM hafbe_endpoints.get_op_count_in_block(43000);`
      
      REST call example
      * `GET https://{hafbe-host}/hafbe/blocks/10000/operations-count`
      
      * `GET https://{hafbe-host}/hafbe/blocks/43000/operations-count`
    operationId: hafbe_endpoints.get_op_count_in_block
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
          Given block's operations count

          * Returns array of `hafbe_types.op_count_in_block`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hafbe_types.array_of_op_count_in_block'
            example:
              - op_type_id: 0
                count: 1
              - op_type_id: 1
                count: 5
              - op_type_id: 72
                count: 1
      '404':
        description: No block in the database
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_op_count_in_block;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_op_count_in_block(
    "block-num" INT
)
RETURNS SETOF hafbe_types.op_count_in_block 
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

RETURN QUERY
  SELECT 
    ov.op_type_id,
    COUNT(ov.op_type_id) as count 
  FROM hive.operations_view ov
  WHERE ov.block_num = "block-num"
  GROUP BY ov.op_type_id
;

END
$$;

RESET ROLE;
