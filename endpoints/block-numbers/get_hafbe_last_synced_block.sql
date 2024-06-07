SET ROLE hafbe_owner;

/** openapi:paths
/hafbe/block-numbers/last-synced-block:
  get:
    tags:
      - Blocks
    summary: Haf_block_explorer's last synced block
    description: |
      Get last block-num synced by haf_block_explorer

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_hafbe_last_synced_block();`
      
      REST call example
      * `GET https://{hafbe-host}/hafbe/block-numbers/last-synced-block`
    operationId: hafbe_endpoints.get_hafbe_last_synced_block
    parameters:
    responses:
      '200':
        description: |
          Last synced block
          
          * Returns `INT`
        content:
          application/json:
            schema:
              type: integer
            example: 3131
      '404':
        description: No blocks synced
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_hafbe_last_synced_block;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_hafbe_last_synced_block()
RETURNS INT 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN

  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);
  RETURN current_block_num FROM hive.contexts WHERE name = 'hafbe_app';
END
$$;

RESET ROLE;
