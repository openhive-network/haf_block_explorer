SET ROLE hafbe_owner;

-- Witness page endpoint
/** openapi:paths
/hafbe/witnesses/{account-name}/votes/history:
  get:
    tags:
      - Witnesses
    summary: Get the history of votes for this witness
    description: |
      Get information about each vote cast for this witness

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_witness_votes_history('gtg');`
      
      * `SELECT * FROM hafbe_endpoints.get_witness_votes_history('blocktrades');`
      
      REST call example
      * `GET https://{hafbe-host}/hafbe/witnesses/gtg/votes/history`

      * `GET https://{hafbe-host}/hafbe/witnesses/blocktrades/votes/history`
    operationId: hafbe_endpoints.get_witness_votes_history
    parameters:
      - in: path
        name: account-name
        required: true
        schema:
          type: string
        description: The witness account name
      - in: query
        name: sort
        required: false
        schema:
          $ref: '#/components/schemas/hafbe_types.order_by_votes'
          default: timestamp
        description: |
          Sort order:

           * `voter` - total number of voters casting their votes for each witness.  this probably makes no sense for this call???

           * `vests` - total weight of vests casting their votes for each witness

           * `account_vests` - total weight of vests owned by accounts voting for each witness

           * `proxied_vests` - total weight of vests owned by accounts who proxy their votes to a voter voting for each witness

           * `timestamp` - the time the voter last changed their vote???
      - in: query
        name: direction
        required: false
        schema:
          $ref: '#/components/schemas/hafbe_types.sort_direction'
          default: desc
      - in: query
        name: limit
        required: false
        schema:
          type: integer
          default: 100
        description: Return at most `limit` voters
        description: |
          Sort order:

           * `asc` - Ascending, from A to Z or smallest to largest

           * `desc` - Descending, from Z to A or largest to smallest
      - in: query
        name: from_time
        required: false
        schema:
          type: string
          format: date-time
          x-sql-default-value: "'1970-01-01T00:00:00'::TIMESTAMP"
        description: Return only votes newer than `from_time`
      - in: query
        name: to_time
        required: false
        schema:
          type: string
          format: date-time
          x-sql-default-value: now()
        description: Return only votes older than `to_time`
    responses:
      '200':
        description: |
          The number of voters currently voting for this witness

          * Returns array of `hafbe_types.witness_vote_history_record`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hafbe_types.array_of_witness_vote_history_records'
            example:
              - voter: reugie
                approve: true
                vests: 1492852870616
                vests_hive_power: 863149
                account_vests: 1492852870616
                account_hive_power: 863149
                proxied_vests: 0
                proxied_hive_power: 0
                timestamp: '2024-03-27T14:46:09.000Z'
              - voter: cooperclub
                approve: true
                vests: 8238935864379
                vests_hive_power: 4763650
                account_vests: 8238935864379
                account_hive_power: 4763650
                proxied_vests: 0
                proxied_hive_power: 0
                timestamp: '2024-03-27T14:42:06.000Z'
      '404':
        description: No such witness
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_witness_votes_history;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_witness_votes_history(
    "account-name" TEXT,
    "sort" hafbe_types.order_by_votes = 'timestamp',
    "direction" hafbe_types.sort_direction = 'desc',
    "limit" INT = 100,
    "from_time" TIMESTAMP = '1970-01-01T00:00:00'::TIMESTAMP,
    "to_time" TIMESTAMP = now()
)
RETURNS SETOF hafbe_types.witness_votes_history_record 
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
BEGIN

PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

RETURN QUERY EXECUTE format(
  $query$

  WITH select_range AS MATERIALIZED (
    SELECT 
      (SELECT av.name FROM hive.accounts_view av WHERE av.id = wvh.voter_id)::TEXT AS voter,
      * 
    FROM hafbe_app.witness_votes_history_cache wvh
    WHERE wvh.witness_id = %L
    AND wvh.timestamp BETWEEN  %L AND  %L
    ORDER BY wvh.timestamp DESC
    LIMIT %L
  ),
  get_block_num AS MATERIALIZED
    (SELECT bv.num AS block_num FROM hive.blocks_view bv ORDER BY bv.num DESC LIMIT 1),
  select_votes_history AS (
  SELECT
    wvh.voter, wvh.approve, 
    (wvh.account_vests + wvh.proxied_vests ) AS vests, 
    (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), (wvh.account_vests + wvh.proxied_vests) ))::BIGINT AS vests_hive_power,
    wvh.account_vests AS account_vests, 
    (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), wvh.account_vests))::BIGINT AS account_hive_power,
    wvh.proxied_vests AS proxied_vests,
    (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), wvh.proxied_vests))::BIGINT AS proxied_hive_power,
    wvh.timestamp AS timestamp
  FROM select_range wvh
  )
  SELECT * FROM select_votes_history
  ORDER BY
    (CASE WHEN %L = 'desc' THEN  %I ELSE NULL END) DESC,
    (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC
  ;
  $query$,
  _witness_id,"from_time", "to_time", "limit", "direction", "sort", "direction", "sort"
) res;
END
$$;

RESET ROLE;
