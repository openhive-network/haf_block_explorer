SET ROLE hafbe_owner;

-- Witness page endpoint
/** openapi:paths
/hafbe/witnesses:
  get:
    tags:
      - Witnesses
    summary: List witnesses
    description: |
      List all witnesses (both active and standby)

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_witnesses();`
      * `SELECT * FROM hafbe_endpoints.get_witnesses(10);`
      
      REST call example
      * `GET https://{hafbe-host}/hafbe/witnesses`
      * `GET https://{hafbe-host}/hafbe/witnesses?limit=10`
    operationId: hafbe_endpoints.get_witnesses
    parameters:
      - in: query
        name: limit
        required: false
        schema:
          type: integer
          default: 100
        description: For pagination, return at most `limit` witnesses
      - in: query
        name: offset
        required: false
        schema:
          type: integer
          default: 0
        description: For pagination, start at the `offset`th witness
      - in: query
        name: sort
        required: false
        schema:
          $ref: '#/components/schemas/hafbe_types.order_by_witness'
          default: votes
        description: |
          Sort order:

           * `witness` - the witness' name

           * `rank` - their current rank (highest weight of votes => lowest rank)

           * `url` - the witness' url

           * `votes` - total number of votes

           * `votes_daily_change` - change in `votes` in the last 24 hours

           * `voters_num` - total number of voters approving the witness

           * `voters_num_daily_change` - change in `voters_num` in the last 24 hours

           * `price_feed` - their current published value for the HIVE/HBD price feed

           * `bias` - if HBD is trading at only 0.90 USD on exchanges, the witness might set:
                  base: 0.250 HBD
                  quote: 1.100 HIVE
                In this case, the bias is 10%

           * `feed_age` - how old their feed value is

           * `block_size` - the block size they're voting for

           * `signing_key` - the witness' block-signing public key

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

          * Returns array of `hafbe_types.witness`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hafbe_types.array_of_witnesses'
            example:
              - witness: arcange
                rank: 1
                url: >-
                  https://peakd.com/witness-category/@arcange/witness-update-202103
                vests: 141591182132060780
                votes_hive_power: 81865807173
                votes_daily_change: 39841911089
                votes_daily_change_hive_power: 23036
                voters_num: 4481
                voters_num_daily_change: 5
                price_feed: 0.302
                bias: 0
                feed_age: '00:45:20.244402'
                block_size: 65536
                signing_key: STM6wjYfYn728hR5yXNBS5GcMoACfYymKEWW1WFzDGiMaeo9qUKwH
                version: 1.27.4
                missed_blocks: 697
                hbd_interest_rate: 2000
              - witness: gtg
                rank: 2
                url: https://gtg.openhive.network
                vests: 141435014237847520
                votes_hive_power: 81775513339
                votes_daily_change: 186512763933
                votes_daily_change_hive_power: 107839
                voters_num: 3131
                voters_num_daily_change: 4
                price_feed: 0.3
                bias: 0
                feed_age: '00:55:26.244402'
                block_size: 65536
                signing_key: STM5dLh5HxjjawY4Gm6o6ugmJUmEXgnfXXXRJPRTxRnvfFBJ24c1M
                version: 1.27.5
                missed_blocks: 986
                hbd_interest_rate: 1500
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_witnesses;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_witnesses(
    "limit" INT = 100,
    "offset" INT = 0,
    "sort" hafbe_types.order_by_witness = 'votes',
    "direction" hafbe_types.sort_direction = 'desc'
)
RETURNS SETOF hafbe_types.witness 
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

RETURN QUERY EXECUTE format(
  $query$

  WITH limited_set AS (
    SELECT
      cw.witness_id, 
      (SELECT av.name FROM hive.accounts_view av WHERE av.id = cw.witness_id)::TEXT AS witness,
      cw.url,
      cw.price_feed,
      cw.bias,
      (NOW() - cw.feed_updated_at)::INTERVAL AS feed_age,
      cw.block_size, 
      cw.signing_key, 
      cw.version, 
      b.rank, 
      COALESCE(b.votes,0) AS votes, 
      COALESCE(b.voters_num,0) AS voters_num, 
      COALESCE(c.votes_daily_change, 0) AS votes_daily_change, 
      COALESCE(c.voters_num_daily_change,0) AS voters_num_daily_change,
      COALESCE(
      (
        SELECT count(*) as missed
        FROM hive.account_operations_view aov
        WHERE aov.op_type_id = 86 AND aov.account_id = cw.witness_id
      )::INT
      ,0) AS missed_blocks,
      COALESCE(cw.hbd_interest_rate,0) AS hbd_interest_rate
    FROM hafbe_app.current_witnesses cw
    LEFT JOIN hafbe_app.witness_votes_cache b ON b.witness_id = cw.witness_id
    LEFT JOIN hafbe_app.witness_votes_change_cache c ON c.witness_id = cw.witness_id
  ),
  limited_set_order AS MATERIALIZED (
    SELECT * FROM limited_set
    ORDER BY
      (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
      (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC
    OFFSET %L
    LIMIT %L
  ),
get_block_num AS MATERIALIZED
(SELECT bv.num AS block_num FROM hive.blocks_view bv ORDER BY bv.num DESC LIMIT 1)

  SELECT
    ls.witness, 
    ls.rank, 
    ls.url,
    ls.votes,
    (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), ls.votes))::BIGINT, 
    ls.votes_daily_change,
    (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), ls.votes_daily_change))::BIGINT, 
    ls.voters_num,
    ls.voters_num_daily_change,
    ls.price_feed, 
    ls.bias, 
    ls.feed_age, 
    ls.block_size, 
    ls.signing_key, 
    ls.version,
    ls.missed_blocks,
    ls.hbd_interest_rate
  FROM limited_set_order ls
  ORDER BY
    (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
    (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC

  $query$,
  "direction", "sort", "direction", "sort", "offset","limit",
  "direction", "sort", "direction", "sort"
)
;

END
$$;

RESET ROLE;
