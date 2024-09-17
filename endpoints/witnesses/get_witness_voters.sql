SET ROLE hafbe_owner;

-- Witness page endpoint
/** openapi:paths
/witnesses/{account-name}/voters:
  get:
    tags:
      - Witnesses
    summary: Get information about the voters for a witness
    description: |
      Get information about the voters voting for a given witness

      SQL example      
      * `SELECT * FROM hafbe_endpoints.get_witness_voters(''blocktrades'');`
      
      REST call example
      * `GET ''https://%1$s/hafbe-api/witnesses/blocktrades/voters?result-limit=2''`
    operationId: hafbe_endpoints.get_witness_voters
    parameters:
      - in: path
        name: account-name
        required: true
        schema:
          type: string
        description: witness account name
      - in: query
        name: sort
        required: false
        schema:
          $ref: '#/components/schemas/hafbe_types.order_by_votes'
          default: vests
        description: |
          Sort order:

           * `voter` - account name of voter

           * `vests` - total voting power = account_vests + proxied_vests of voter

           * `account_vests` - direct vests of voter

           * `proxied_vests` - proxied vests of voter

           * `timestamp` - last time voter voted for the witness
      - in: query
        name: direction
        required: false
        schema:
          $ref: '#/components/schemas/hafbe_types.sort_direction'
          default: desc
        description: |
          Sort order:

           * `asc` - Ascending, from A to Z or smallest to largest

           * `desc` - Descending, from Z to A or largest to smallest
      - in: query
        name: result-limit
        required: false
        schema:
          type: integer
          default: 2147483647
        description: Return at most `result-limit` voters
    responses:
      '200':
        description: |
          The number of voters currently voting for this witness

          * Returns `JSON`
        content:
          application/json:
            schema:
              type: string
              x-sql-datatype: JSON
            example:
              - {
                  "votes_updated_at": "2024-08-29T12:05:08.097875",
                  "voters": [
                    {
                      "voter_name": "blocktrades",
                      "vests": "13155953611548185",
                      "account_vests": "8172549681941451",
                      "proxied_vests": "4983403929606734",
                      "timestamp": "2016-04-15T02:19:57"
                    },
                    {
                      "voter_name": "dan",
                      "vests": "9928811304950768",
                      "account_vests": "9928811304950768",
                      "proxied_vests": "0",
                      "timestamp": "2016-06-27T12:41:42"
                    }
                  ]
                }
      '404':
        description: No such witness
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_witness_voters;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_witness_voters(
    "account-name" TEXT,
    "sort" hafbe_types.order_by_votes = 'vests',
    "direction" hafbe_types.sort_direction = 'desc',
    "result-limit" INT = 2147483647
)
RETURNS JSON 
-- openapi-generated-code-end
LANGUAGE 'plpgsql'
STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
AS
$$
BEGIN
  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

  RETURN (
    SELECT json_build_object(
      'votes_updated_at', (SELECT last_updated_at 
          FROM hafbe_app.witnesses_cache_config
          ),
      'voters', 
        (SELECT to_json(array_agg(row)) FROM (
          SELECT * FROM hafbe_backend.get_witness_voters(
            "account-name",
            "sort",
            "direction",
            "result-limit")
      ) row)
    )
  );
END
$$;

RESET ROLE;
