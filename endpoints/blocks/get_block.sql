SET ROLE hafbe_owner;

/** openapi:paths
/hafbe/blocks/{block-num}:
  get:
    tags:
      - Blocks
    summary: Informations about block
    description: |
      Lists the parameters of the block provided by the user

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_block(10000);`

      * `SELECT * FROM hafbe_endpoints.get_block(43000);`
      
      REST call example
      * `GET https://{hafbe-host}/hafbe/blocks/10000`
      
      * `GET https://{hafbe-host}/hafbe/blocks/43000`
    operationId: hafbe_endpoints.get_block
    parameters:
      - in: path
        name: block-num
        required: true
        schema:
          type: integer
        description: Given block number
    responses:
      '200':
        description: |
          Given block's stats

          * Returns `hafbe_types.block`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hafbe_types.block'
            example:
              - block_num: 1231
                hash: \\x000004cf8319149b0743acdcf2a17a332677fb0f
                prev: \\x000004ce0536f08f1e09c3dc7b12b8ddf13f1c5a
                producer_account: 'producer_account'
                transaction_merkle_root: \\x0000000000000000000000000000000000000000
                extensions: NULL
                witness_signature: \\x207f255f2d6c69c04ccfa4a541792a773412307735ccf96ba9e12d9c84b714c4711cf1d1bed561994c46daf33a24e8071f15f92
                signing_key: STM65wH1LZ7BfSHcK69SShnqCAH5xdoSZpGkUjmzHJ5GCuxEK9V5G
                hbd_interest_rate: 1000
                total_vesting_fund_hive: 28000
                total_vesting_shares: 28000000
                total_reward_fund_hive: 2462000
                virtual_supply: 4932000
                current_supply: 4932000
                current_hbd_supply: 0
                dhf_interval_ledger: 0
                created_at: '2016-03-24T17:07:15'
                age: '2993 days 15:24:08.630023'
      '404':
        description: No blocks in the database
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_block;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_block(
    "block-num" INT
)
RETURNS hafbe_types.block 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
SET JIT = OFF
SET join_collapse_limit = 16
SET from_collapse_limit = 16
AS
$$
BEGIN

IF "block-num" <= hive.app_get_irreversible_block() THEN
  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=31536000"}]', true);
ELSE
  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);
END IF;

RETURN (
SELECT ROW(
  bv.num,   
  bv.hash,
  bv.prev,
  (SELECT av.name FROM hive.accounts_view av WHERE av.id = bv.producer_account_id)::TEXT,
  bv.transaction_merkle_root,
  bv.extensions,
  bv.witness_signature,
  bv.signing_key,
  bv.hbd_interest_rate::numeric,
  bv.total_vesting_fund_hive::numeric,
  bv.total_vesting_shares::numeric,
  bv.total_reward_fund_hive::numeric,
  bv.virtual_supply::numeric,
  bv.current_supply::numeric,
  bv.current_hbd_supply::numeric,
  bv.dhf_interval_ledger::numeric,
  bv.created_at,
  NOW() - bv.created_at)
FROM hive.blocks_view bv
WHERE bv.num = "block-num"
);

END
$$;

RESET ROLE;
