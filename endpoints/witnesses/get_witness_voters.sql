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
      * `SELECT * FROM hafbe_endpoints.get_witness_voters('gtg');`
      
      * `SELECT * FROM hafbe_endpoints.get_witness_voters('blocktrades');`
      
      REST call example
      * `GET https://{hafbe-host}/hafbe/witnesses/gtg/voters`

      * `GET https://{hafbe-host}/hafbe/witnesses/blocktrades/voters`
    operationId: hafbe_endpoints.get_witness_voters
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
          default: vests
        description: |
          Sort order:

           * `voter` - total number of voters casting their votes for each witness.  this probably makes no sense for call???

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

          * Returns array of `hafbe_types.witness_voter`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hafbe_types.array_of_witness_voters'
            example:
              - voter: reugie
                vests: 1492852870616
                vests_hive_power: 863149
                account_vests: 1492852870616
                account_hive_power: 863149
                proxied_vests: 0
                proxied_hive_power: 0
                timestamp: '2024-03-27T14:46:09.000Z'
              - voter: cooperclub
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
DROP FUNCTION IF EXISTS hafbe_endpoints.get_witness_voters;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_witness_voters(
    "account-name" TEXT,
    "sort" hafbe_types.order_by_votes = 'vests',
    "direction" hafbe_types.sort_direction = 'desc',
    "result-limit" INT = 2147483647
)
RETURNS SETOF hafbe_types.witness_voter 
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

  WITH limited_set AS (
    SELECT 
      (SELECT av.name FROM hive.accounts_view av WHERE av.id = wvsc.voter_id)::TEXT AS voter,
      wvsc.voter_id, wvsc.vests, wvsc.account_vests, wvsc.proxied_vests, wvsc.timestamp
    FROM hafbe_app.witness_voters_stats_cache wvsc
    WHERE witness_id = %L   
  ),
  limited_set_order AS MATERIALIZED (
    SELECT * FROM limited_set
    ORDER BY
      (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
      (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC  
    LIMIT %L
  ),
  get_block_num AS MATERIALIZED
  (SELECT bv.num AS block_num FROM hive.blocks_view bv ORDER BY bv.num DESC LIMIT 1)

  SELECT ls.voter, 
  ls.vests,
  (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), ls.vests))::BIGINT,
  ls.account_vests,
  (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), ls.account_vests))::BIGINT,
  ls.proxied_vests,
  (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), ls.proxied_vests))::BIGINT,
  ls.timestamp
  FROM limited_set_order ls
  ORDER BY
    (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
    (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC
  ;

  $query$,
  _witness_id, "direction", "sort", "direction", "sort", "result-limit",
  "direction", "sort", "direction", "sort"
) res;

END
$$;

RESET ROLE;
