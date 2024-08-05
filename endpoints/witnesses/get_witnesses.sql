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
      * `SELECT * FROM hafbe_endpoints.get_witnesses(2);`
      
      REST call example
      * `GET ''https://%1$s/hafbe/witnesses?result-limit=2''`
    operationId: hafbe_endpoints.get_witnesses
    parameters:
      - in: query
        name: result-limit
        required: false
        schema:
          type: integer
          default: 100
        description: For pagination, return at most `result-limit` witnesses
      - in: query
        name: offset
        required: false
        schema:
          type: integer
          default: 0
        description: For pagination, start at the `offset` witness
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

           * `bias` - if HBD is trading at only 0.90 USD on exchanges, the witness might set:
                  base: 0.250 HBD
                  quote: 1.100 HIVE
                In this case, the bias is 10%%

           * `block_size` - the block size they''re voting for

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

          * Returns array of `hafbe_types.witness`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hafbe_types.array_of_witnesses'
            example:
              - witnes": "roadscape"
                rank: 1
                url: "https://steemit.com/witness-category/@roadscape/witness-roadscape"
                vests: "94172201023355097"
                vests_hive_power: 31350553033
                votes_daily_change: "0"
                votes_daily_change_hive_power: 0,
                voters_num: 306
                voters_num_daily_change: 0
                price_feed: 0.539
                bias: 0
                feed_updated_at: "2016-09-15T16:07:42"
                block_size: 65536
                signing_key: "STM5AS7ZS33pzTf1xbTi8ZUaUeVAZBsD7QXGrA51HvKmvUDwVbFP9"
                version: "0.13.0"
                missed_blocks: 129
                hbd_interest_rate: 1000
              - witness: "arhag"
                rank: 2
                url: "https://steemit.com/witness-category/@arhag/witness-arhag"
                vests: "91835048921097725"
                vests_hive_power: 30572499530
                votes_daily_change: "0"
                votes_daily_change_hive_power: 0
                voters_num: 348
                voters_num_daily_change: 0
                price_feed: 0.536
                bias: 0
                feed_updated_at: "2016-09-15T19:31:18"
                block_size: 65536
                signing_key: "STM8kvk4JH2m6ZyHBGNor4qk2Zwdi2MJAjMYUpfqiicCKu7HqAeZh"
                version: "0.13.0"
                missed_blocks: 61
                hbd_interest_rate: 1000
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_witnesses;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_witnesses(
    "result-limit" INT = 100,
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
      cw.feed_updated_at,
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
    ls.votes::TEXT,
    (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), ls.votes))::BIGINT, 
    ls.votes_daily_change::TEXT,
    (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), ls.votes_daily_change))::BIGINT, 
    ls.voters_num,
    ls.voters_num_daily_change,
    ls.price_feed, 
    ls.bias, 
    ls.feed_updated_at,
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
  "direction", "sort", "direction", "sort", "offset","result-limit",
  "direction", "sort", "direction", "sort"
)
;

END
$$;

RESET ROLE;
