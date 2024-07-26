SET ROLE hafbe_owner;

-- Witness page endpoint
/** openapi:paths
/witnesses/{account-name}:
  get:
    tags:
      - Witnesses
    summary: Get a single witness
    description: |
      Return a single witness given their account name

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_witness('gtg');`

      * `SELECT * FROM hafbe_endpoints.get_witness('blocktrades');`
      
      REST call example
      * `GET https://{hafbe-host}/hafbe/witnesses/gtg`
      
      * `GET https://{hafbe-host}/hafbe/witnesses/blocktrades`
    operationId: hafbe_endpoints.get_witness
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
          The witness stats

          * Returns `hafbe_types.witness`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hafbe_types.witness'
            example:
              witness: arcange
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
      '404':
        description: No such witness
*/
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_witness;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_witness(
    "account-name" TEXT
)
RETURNS hafbe_types.witness 
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
WITH limited_set AS (
  SELECT
    cw.witness_id, av.name::TEXT AS witness,
    cw.url, cw.price_feed, cw.bias,
    (NOW() - cw.feed_updated_at)::INTERVAL AS feed_age,
    cw.feed_updated_at,
    cw.block_size, cw.signing_key, cw.version,
    COALESCE(
      (
        SELECT count(*) as missed
        FROM hive.account_operations_view aov
        WHERE aov.op_type_id = 86 AND aov.account_id = cw.witness_id
      )::INT
    ,0) AS missed_blocks,
    COALESCE(cw.hbd_interest_rate, 0) AS hbd_interest_rate
  FROM hive.accounts_view av
  JOIN hafbe_app.current_witnesses cw ON av.id = cw.witness_id
  WHERE av.name = "account-name"
),
get_block_num AS MATERIALIZED
(SELECT bv.num AS block_num FROM hive.blocks_view bv ORDER BY bv.num DESC LIMIT 1)

SELECT ROW(
  ls.witness, 
  all_votes.rank, 
  ls.url,
  COALESCE(all_votes.votes, 0),
  (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), COALESCE(all_votes.votes, 0)))::BIGINT, 
  COALESCE(wvcc.votes_daily_change, 0),
  (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), COALESCE(wvcc.votes_daily_change, 0)))::BIGINT, 
  COALESCE(all_votes.voters_num, 0),
  COALESCE(wvcc.voters_num_daily_change, 0),
  ls.price_feed, 
  ls.bias, 
  ls.feed_age,
  ls.feed_updated_at,
  ls.block_size, 
  ls.signing_key, 
  ls.version,
  ls.missed_blocks, 
  ls.hbd_interest_rate
  )
FROM limited_set ls
LEFT JOIN hafbe_app.witness_votes_cache all_votes ON all_votes.witness_id = ls.witness_id 
LEFT JOIN hafbe_app.witness_votes_change_cache wvcc ON wvcc.witness_id = ls.witness_id

);

END
$$;

RESET ROLE;
