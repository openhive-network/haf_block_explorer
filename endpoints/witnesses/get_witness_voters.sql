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
      * `SELECT * FROM hafbe_endpoints.get_witness_voters(''blocktrades'',1,2);`
      
      REST call example
      * `GET ''https://%1$s/hafbe-api/witnesses/blocktrades/voters?page-size=2''`
    operationId: hafbe_endpoints.get_witness_voters
    parameters:
      - in: path
        name: account-name
        required: true
        schema:
          type: string
        description: witness account name
      - in: query
        name: voter-name
        required: false
        schema:
          type: string
          default: NULL
        description: |
          When provided, only votes associated with this account will be included in the results, 
          allowing for targeted analysis of an individual account''s voting activity.
      - in: query
        name: page
        required: false
        schema:
          type: integer
          default: 1
        description: |
          Return page on `page` number, defaults to `1`
      - in: query
        name: page-size
        required: false
        schema:
          type: integer
          default: 100
        description: Return max `page-size` operations per page, defaults to `100`
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
    responses:
      '200':
        description: |
          The number of voters currently voting for this witness

          * Returns `hafbe_types.witness_voter_history`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hafbe_types.witness_voter_history'
            example: {
              "total_votes": 263,
              "total_pages": 132,
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
    "voter-name" TEXT = NULL,
    "page" INT = 1,
    "page-size" INT = 100,
    "sort" hafbe_types.order_by_votes = 'vests',
    "direction" hafbe_types.sort_direction = 'desc'
)
RETURNS hafbe_types.witness_voter_history 
-- openapi-generated-code-end
LANGUAGE 'plpgsql'
STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
AS
$$
DECLARE
  _witness_id INT        := hafbe_backend.get_witness_id("account-name");
  _filter_account_id INT := hafah_backend.get_account_id("voter-name", FALSE);
  _ops_count INT;
  _total_pages INT;

  _result hafbe_types.witness_voter[];
BEGIN
  PERFORM hafbe_exceptions.validate_limit("page-size", 10000);
  PERFORM hafbe_exceptions.validate_negative_limit("page-size");
  PERFORM hafbe_exceptions.validate_negative_page("page");

  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

  _ops_count   := hafbe_backend.get_witness_voters_count(_witness_id, _filter_account_id);
  _total_pages := hafah_backend.total_pages(_ops_count, "page-size");

  PERFORM hafbe_exceptions.validate_page("page", _total_pages);

  _result := array_agg(row) FROM (
    SELECT 
      ba.voter_name,
      ba.vests,
      ba.account_vests,
      ba.proxied_vests,
      ba.timestamp
    FROM hafbe_backend.get_witness_voters(
      _witness_id,
      _filter_account_id,
      "page",
      "page-size",
      "sort",
      "direction"
    ) ba
  ) row;

  RETURN (
    COALESCE(_ops_count,0),
    COALESCE(_total_pages,0),
    COALESCE(_result, '{}'::hafbe_types.witness_voter[])
  )::hafbe_types.witness_voter_history;

END
$$;

RESET ROLE;
