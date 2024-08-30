SET ROLE hafbe_owner;

/** openapi:paths
/operation-type-counts:
  get:
    tags:
      - Other
    summary: Returns histogram of operation types in blocks.
    description: |
      Lists the counts of operations in result-limit blocks along with their creators. 
      If block-num is not specified, the result includes the counts of operations in the most recent blocks.
      

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_latest_blocks(1);`
      
      REST call example      
      * `GET ''https://%1$s/hafbe-api/operation-type-counts?result-limit=1''`
    operationId: hafbe_endpoints.get_latest_blocks
    parameters:
      - in: query
        name: block-num
        required: false
        schema:
          type: integer
          default: NULL
        description: Given block number, defaults to `NULL`
      - in: query
        name: result-limit
        required: false
        schema:
          type: integer
          default: 20
        description: |
          Specifies number of blocks to return starting with head block, defaults to `20`
    responses:
      '200':
        description: |
          Operation counts for each block 

          * Returns array of `hafbe_types.latest_blocks`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hafbe_types.array_of_latest_blocks'
            example:
              - block_num: 5000000
                witness: ihashfury
                ops_count: [
                    {"count": 1,"op_type_id": 64},
                    {"count": 1,"op_type_id": 9},
                    {"count": 1,"op_type_id": 80},
                    {"count": 1,"op_type_id": 5}
                  ]
      '404':
        description: No blocks in the database
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_latest_blocks;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_latest_blocks(
    "block-num" INT = NULL,
    "result-limit" INT = 20
)
RETURNS SETOF hafbe_types.latest_blocks 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
SET JIT = OFF
SET join_collapse_limit = 16
SET from_collapse_limit = 16
AS
$$
DECLARE 
  _is_block_filter BOOLEAN := ("block-num" IS NULL);
BEGIN
  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

  RETURN QUERY
    WITH select_block_range AS MATERIALIZED (
      SELECT 
        bv.num as block_num,
        (SELECT av.name FROM hive.accounts_view av WHERE av.id = bv.producer_account_id)::TEXT as witness
      FROM hive.blocks_view bv
      WHERE _is_block_filter OR bv.num <= "block-num"
      ORDER BY bv.num DESC LIMIT "result-limit"
    ),
    join_operations AS MATERIALIZED (
      SELECT 
        sbr.block_num, 
        sbr.witness, 
        COUNT(ov.op_type_id) as count, 
        ov.op_type_id 
      FROM hive.operations_view ov
      JOIN select_block_range sbr ON sbr.block_num = ov.block_num
      GROUP BY ov.op_type_id,sbr.block_num,sbr.witness
    )
    SELECT 
      jo.block_num,
      jo.witness,
      json_agg(
        json_build_object(
          'count', jo.count,
          'op_type_id', jo.op_type_id
        ) 
      ) 
    FROM join_operations jo
    GROUP BY jo.block_num, jo.witness
    ORDER BY jo.block_num DESC
  ;

END
$$;

RESET ROLE;
