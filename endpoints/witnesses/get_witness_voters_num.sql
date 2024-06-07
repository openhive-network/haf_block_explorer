SET ROLE hafbe_owner;

/** openapi:paths
/hafbe/witnesses/{account-name}/voters/count:
  get:
    tags:
      - Witnesses
    summary: Get the number of voters for a witness
    description: |
      Get the number of voters for a witness given their account name

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_witness_voters_num('gtg');`
      
      * `SELECT * FROM hafbe_endpoints.get_witness_voters_num('blocktrades');`
      
      REST call example
      * `GET https://{hafbe-host}/hafbe/witnesses/gtg/voters/count`

      * `GET https://{hafbe-host}/hafbe/witnesses/blocktrades/voters/count`
    operationId: hafbe_endpoints.get_witness_voters_num
    parameters:
      - in: path
        name: account-name
        required: true
        schema:
          type: string
        description: The witness account name
    responses:
      '200':
        description: |
          The number of voters currently voting for this witness

          * Returns `INT`
        content:
          application/json:
            schema:
              type: integer
            example: 3131
      '404':
        description: No such witness
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_witness_voters_num;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_witness_voters_num(
    "account-name" TEXT
)
RETURNS INT 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
DECLARE
  _witness_id INT = hafbe_backend.get_account_id("account-name");
BEGIN
  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);
  RETURN COUNT(*) FROM hafbe_app.current_witness_votes WHERE witness_id = _witness_id;
END
$$;

RESET ROLE;
