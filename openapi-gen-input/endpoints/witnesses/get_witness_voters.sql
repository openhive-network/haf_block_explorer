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

          * Returns `JSON`
        content:
          application/json:
            schema:
              type: string
              x-sql-datatype: JSON
            example:
              - {
                  "total_operations": 263,
                  "total_pages": 132,
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
-- openapi-generated-code-end
LANGUAGE 'plpgsql'
STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
AS
$$
DECLARE
  _witness_id INT = hafbe_backend.get_account_id("account-name");
  _ops_count INT;
  _calculate_total_pages INT;
BEGIN
  PERFORM hafbe_exceptions.validate_limit("page-size", 10000);
  PERFORM hafbe_exceptions.validate_negative_limit("page-size");
  PERFORM hafbe_exceptions.validate_negative_page("page");

  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

    --count for given parameters 
  SELECT COUNT(*) INTO _ops_count
  FROM hafbe_app.witness_voters_stats_cache 
  WHERE witness_id = _witness_id;

  --amount of pages
  SELECT 
    (
      CASE WHEN (_ops_count % "page-size") = 0 THEN 
        _ops_count/"page-size" 
      ELSE ((_ops_count/"page-size") + 1) 
      END
    )::INT INTO _calculate_total_pages;

  PERFORM hafbe_exceptions.validate_page("page", _calculate_total_pages);

  RETURN (
    SELECT json_build_object(
      'total_operations', _ops_count,
      'total_pages', _calculate_total_pages,
      'votes_updated_at', (SELECT last_updated_at 
          FROM hafbe_app.witnesses_cache_config
          ),
      'voters', 
        COALESCE((SELECT to_json(array_agg(row)) FROM (
          SELECT * FROM hafbe_backend.get_witness_voters(
            _witness_id,
            "page",
            "page-size",
            "sort",
            "direction")
      ) row), '[]')
    )
  );
END
$$;

RESET ROLE;
