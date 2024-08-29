SET ROLE hafbe_owner;

-- Witness page endpoint
/** openapi:paths
/witnesses/{account-name}/votes/history:
  get:
    tags:
      - Witnesses
    summary: Get the history of votes for this witness.
    description: |
      Get information about each vote cast for this witness

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_witness_votes_history(''blocktrades'');`
      
      REST call example
      * `GET ''https://%1$s/hafbe/witnesses/blocktrades/votes/history?result-limit=2''`
    operationId: hafbe_endpoints.get_witness_votes_history
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
          default: timestamp
        description: |
          Sort order:

           * `voter` - account name of voter

           * `vests` - total voting power = account_vests + proxied_vests of voter

           * `account_vests` - direct vests of voter

           * `proxied_vests` - proxied vests of voter

           * `timestamp` - time when user performed vote/unvote operation
      - in: query
        name: direction
        required: false
        schema:
          $ref: '#/components/schemas/hafbe_types.sort_direction'
          default: desc
      - in: query
        name: result-limit
        required: false
        schema:
          type: integer
          default: 100
        description: Return at most `result-limit` voters
        description: |
          Sort order:

           * `asc` - Ascending, from A to Z or smallest to largest

           * `desc` - Descending, from Z to A or largest to smallest
      - in: query
        name: start-date
        required: false
        schema:
          type: string
          format: date-time
          default: NULL
        description: Return only votes newer than `start-date`
      - in: query
        name: end-date
        required: false
        schema:
          type: string
          format: date-time
          x-sql-default-value: now()
        description: Return only votes older than `end-date`
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
                  "votes_history": [
                    {
                      "voter_name": "jeremyfromwi",
                      "approve": true,
                      "vests": "441156952466",
                      "votes_hive_power": 146864,
                      "account_vests": "441156952466",
                      "account_hive_power": 146864,
                      "proxied_vests": "0",
                      "proxied_hive_power": 0,
                      "timestamp": "2016-09-15T07:07:15"
                    },
                    {
                      "voter_name": "cryptomental",
                      "approve": true,
                      "vests": "686005633844",
                      "votes_hive_power": 228376,
                      "account_vests": "686005633844",
                      "account_hive_power": 228376,
                      "proxied_vests": "0",
                      "proxied_hive_power": 0,
                      "timestamp": "2016-09-15T07:00:51"
                    }
                  ]
                }
      '404':
        description: No such witness
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_witness_votes_history;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_witness_votes_history(
    "account-name" TEXT,
    "sort" hafbe_types.order_by_votes = 'timestamp',
    "direction" hafbe_types.sort_direction = 'desc',
    "result-limit" INT = 100,
    "start-date" TIMESTAMP = NULL,
    "end-date" TIMESTAMP = now()
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
      'votes_history', 
        (SELECT to_json(array_agg(row)) FROM (
          SELECT * FROM hafbe_backend.get_witness_votes_history(
            "account-name",
            "sort",
            "direction",
            "result-limit",
            "start-date",
            "end-date")
      ) row)
    )
  );
END
$$;

RESET ROLE;
