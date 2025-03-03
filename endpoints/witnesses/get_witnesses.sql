SET ROLE hafbe_owner;

-- Witness page endpoint
/** openapi:paths
/witnesses:
  get:
    tags:
      - Witnesses
    summary: List witnesses
    description: |
      List all witnesses (both active and standby)

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_witnesses(1,2);`
      
      REST call example
      * `GET ''https://%1$s/hafbe-api/witnesses?page-size=2''`
    operationId: hafbe_endpoints.get_witnesses
    parameters:
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
          $ref: '#/components/schemas/hafbe_types.order_by_witness'
          default: votes
        description: |
          Sort key:

           * `witness` - the witness name

           * `rank` - their current rank (highest weight of votes => lowest rank)

           * `url` - the witness url

           * `votes` - total number of votes

           * `votes_daily_change` - change in `votes` in the last 24 hours

           * `voters_num` - total number of voters approving the witness

           * `voters_num_daily_change` - change in `voters_num` in the last 24 hours

           * `price_feed` - their current published value for the HIVE/HBD price feed

           * `feed_updated_at` - feed update timestamp

           * `bias` - if HBD is trading at only 0.90 USD on exchanges, the witness might set:
                  base: 0.250 HBD
                  quote: 1.100 HIVE
                In this case, the bias is 10%%

           * `block_size` - the block size they are voting for

           * `signing_key` - the witness'' block-signing public key

           * `version` - the version of hived the witness is running
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
          The list of witnesses

          * Returns `JSON`
        content:
          application/json:
            schema:
              type: string
              x-sql-datatype: JSON
            example: {
              "total_operations": 731,
              "total_pages": 366,
              "votes_updated_at": "2024-08-29T12:05:08.097875",
              "witnesses": [
                {
                  "witness_name": "roadscape",
                  "rank": 1,
                  "url": "https://steemit.com/witness-category/@roadscape/witness-roadscape",
                  "vests": "94172201023355097",
                  "votes_daily_change": "0",
                  "voters_num": 306,
                  "voters_num_daily_change": 0,
                  "price_feed": 0.539,
                  "bias": 0,
                  "feed_updated_at": "2016-09-15T16:07:42",
                  "block_size": 65536,
                  "signing_key": "STM5AS7ZS33pzTf1xbTi8ZUaUeVAZBsD7QXGrA51HvKmvUDwVbFP9",
                  "version": "0.13.0",
                  "missed_blocks": 129,
                  "hbd_interest_rate": 1000,
                  "last_confirmed_block_num": 4999986,
                  "account_creation_fee": 2000
                },
                {
                  "witness_name": "arhag",
                  "rank": 2,
                  "url": "https://steemit.com/witness-category/@arhag/witness-arhag",
                  "vests": "91835048921097725",
                  "votes_daily_change": "0",
                  "voters_num": 348,
                  "voters_num_daily_change": 0,
                  "price_feed": 0.536,
                  "bias": 0,
                  "feed_updated_at": "2016-09-15T19:31:18",
                  "block_size": 65536,
                  "signing_key": "STM8kvk4JH2m6ZyHBGNor4qk2Zwdi2MJAjMYUpfqiicCKu7HqAeZh",
                  "version": "0.13.0",
                  "missed_blocks": 61,
                  "hbd_interest_rate": 1000,
                  "last_confirmed_block_num": 4999993,
                  "account_creation_fee": 7000
                }
              ]
            }
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_witnesses;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_witnesses(
    "page" INT = 1,
    "page-size" INT = 100,
    "sort" hafbe_types.order_by_witness = 'votes',
    "direction" hafbe_types.sort_direction = 'desc'
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
DECLARE
  _ops_count INT;
  _calculate_total_pages INT;
BEGIN

  PERFORM hafbe_exceptions.validate_limit("page-size", 1000);
  PERFORM hafbe_exceptions.validate_negative_limit("page-size");
  PERFORM hafbe_exceptions.validate_negative_page("page");

  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

  --count for given parameters 
  SELECT COUNT(*) INTO _ops_count
  FROM hafbe_app.current_witnesses;

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
      'witnesses', 
        COALESCE((SELECT to_json(array_agg(row)) FROM (
          SELECT * FROM hafbe_backend.get_witnesses(
            "page",
            "page-size",
            "sort",
            "direction")
      ) row),'[]')
    )
  );
END
$$;

RESET ROLE;
