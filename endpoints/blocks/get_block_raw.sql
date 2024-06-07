SET ROLE hafbe_owner;

/** openapi:paths
/hafbe/blocks/{block-num}/raw-details:
  get:
    tags:
      - Blocks
    summary: Raw informations about block
    description: |
      Lists the raw parameters of the block provided by the user

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_block_raw(10000);`

      * `SELECT * FROM hafbe_endpoints.get_block_raw(43000);`
      
      REST call example
      * `GET https://{hafbe-host}/hafbe/blocks/10000/raw-details`
      
      * `GET https://{hafbe-host}/hafbe/blocks/43000/raw-details`
    operationId: hafbe_endpoints.get_block_raw
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
          Given block's raw stats

          * Returns `hafbe_types.block_raw`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hafbe_types.block_raw'
            example:
              - previous: \\x000004ce0536f08f1e09c3dc7b12b8ddf13f1c5a
                timestamp: '2016-03-24T17:07:15'
                witness: root
                transaction_merkle_root: \\x0000000000000000000000000000000000000000
                extensions: []
                witness_signature: \\x207f255f2d6c69c04ccfa4a541792a773412307735ccf90bd8efb26ba9e12d9c84b714c4711cf1d1bed561994c46daf33a24e8071f15f92
                transactions: []
                block_id: \\x000004cf8319149b0743acdcf2a17a332677fb0f
                signing_key: STM65wH1LZ7BfSHcK69SShnqCAH5xdoSZpGkUjmzHJ5GCuxEK9V5G
                transaction_ids: NULL
      '404':
        description: No blocks in the database
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_block_raw;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_block_raw(
    "block-num" INT
)
RETURNS hafbe_types.block_raw 
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
	previous,
	timestamp,
	witness,
	transaction_merkle_root,	
	extensions,
	witness_signature,
	hive.transactions_to_json(transactions),
	block_id,
	signing_key,
	transaction_ids)
FROM hive.get_block("block-num")
);

END
$$;

RESET ROLE;
