SET ROLE hafbe_owner;

/** openapi:paths
/hafbe/block-numbers/headblock:
  get:
    tags:
      - Block-numbers
    summary: HAF last synced block
    description: |
      Get last block-num in HAF database

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_head_block_num();`
      
      REST call example
      * `GET https://{hafbe-host}/hafbe/block-numbers/headblock`
    operationId: hafbe_endpoints.get_head_block_num
    responses:
      '200':
        description: |
          Last HAF block
          
          * Returns `INT`
        content:
          application/json:
            schema:
              type: integer
            example: 3131
      '404':
        description: No blocks in the database
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_head_block_num;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_head_block_num()
RETURNS INT 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN

  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);
  RETURN bv.num FROM hive.blocks_view bv ORDER BY bv.num DESC LIMIT 1;

END
$$;

RESET ROLE;
