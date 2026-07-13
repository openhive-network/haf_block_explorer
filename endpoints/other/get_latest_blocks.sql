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
          type: string
          default: NULL
        description: |
          Given block, can be represented either by a `block-num` (integer) or a `timestamp` (in the format `YYYY-MM-DD HH:MI:SS`),

          The provided `timestamp` will be converted to a `block-num` by finding the first block 
          where the block''s `created_at` is less than or equal to the given `timestamp` (i.e. `block''s created_at <= timestamp`). 
        
          The function will interpret and convert the input based on its format, example input:

          * `2016-09-15 19:47:21`

          * `5000000`
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

          * Returns array of `hafbe_backend.latest_blocks`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hafbe_backend.array_of_latest_blocks'
            example:
              - {
                  "block_num": 5000000,
                  "witness": "ihashfury",
                  "operations": [
                    {
                      "op_count": 1,
                      "op_type_id": 64
                    },
                    {
                      "op_count": 1,
                      "op_type_id": 9
                    },
                    {
                      "op_count": 1,
                      "op_type_id": 80
                    },
                    {
                      "op_count": 1,
                      "op_type_id": 5
                    }
                  ]
                }
      '404':
        description: No blocks in the database
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_latest_blocks;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_latest_blocks(
    "block-num" TEXT = NULL,
    "result-limit" INT = 20
)
RETURNS SETOF hafbe_backend.latest_blocks 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
SET JIT = OFF
SET join_collapse_limit = 16
SET from_collapse_limit = 16
AS
$$
DECLARE
  __block         INT := hive.convert_to_block_num("block-num");
  _head_block_num INT := hafbe_backend.get_hafbe_head_block();
  -- Normalize the optional param: an explicit NULL ({"result-limit": null}) must fall back to
  -- the signature default. PostgREST applies the default only when a param is OMITTED, not when
  -- it is explicitly null, so a raw NULL would otherwise reach LIMIT NULL (= "no limit") and
  -- return every block. The shared validators now reject NULL as a backstop, but that would
  -- 400 an input whose optional-parameter semantics are simply "use the default" -- so COALESCE
  -- here, exactly as the paginated endpoints do with page / page-size.
  _result_limit   INT := COALESCE("result-limit", 20);
BEGIN
  PERFORM hafbe_backend.validate_limit(_result_limit, 1000, 'result-limit');
  PERFORM hafbe_backend.validate_negative_limit(_result_limit, 'result-limit');

  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

  RETURN QUERY
    WITH select_block_range AS MATERIALIZED (
      SELECT
        bv.num AS block_num,
        (SELECT av.name FROM hive.accounts_view av WHERE av.id = bv.producer_account_id)::TEXT AS witness
      FROM hive.blocks_view bv
      WHERE bv.num <= _head_block_num
        AND bv.num <= COALESCE(__block, _head_block_num)
      ORDER BY bv.num DESC LIMIT _result_limit
    )
    SELECT
      sbr.block_num,
      sbr.witness,
      array_agg(
        (
          bo.op_type_id,
          bo.op_count
        )::hafbe_backend.block_operations
        ORDER BY bo.op_type_id
      )
    FROM select_block_range sbr
    JOIN hafbe_app.block_operations bo ON bo.block_num = sbr.block_num
    GROUP BY sbr.block_num, sbr.witness
    ORDER BY sbr.block_num DESC
  ;

END
$$;

RESET ROLE;
