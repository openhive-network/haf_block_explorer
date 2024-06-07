SET ROLE hafbe_owner;

/** openapi:paths
/hafbe/hafbe-version:
  get:
    tags:
      - Other
    summary: Haf_block_explorer's version
    description: |
      Get haf_block_explorer's last commit hash that determinates its version

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_hafbe_version();`
      
      REST call example
      * `GET https://{hafbe-host}/hafbe/hafbe-version`
    operationId: hafbe_endpoints.get_hafbe_version
    parameters:
    responses:
      '200':
        description: |
          Haf_block_explorer version

          * Returns `TEXT`
        content:
          application/json:
            schema:
              type: string
            example: 'c2fed8958584511ef1a66dab3dbac8c40f3518f0'
      '404':
        description: App not installed
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_hafbe_version;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_hafbe_version()
RETURNS TEXT 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN

--100000s because version of hafbe doesn't change as often, but it may change
PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=100000"}]', true);

RETURN (
	SELECT git_hash
	FROM hafbe_app.version
);

END
$$;

RESET ROLE;
