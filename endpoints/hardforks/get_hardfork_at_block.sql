SET ROLE hafbe_owner;

/** openapi:paths
/hardforks/{block-num}:
  get:
    tags:
      - Hardforks
    summary: The hardfork in force at a block
    description: |
      Returns the most recent hardfork applied at or before the given block: the
      protocol era the block belongs to. A block that applies a hardfork already
      belongs to the era of that hardfork. Blocks before hardfork 1 return hardfork 0, the
      genesis protocol, reported at block 1.

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_hardfork_at_block(45000000);`

      REST call example
      * `GET ''https://%1$s/hafbe-api/hardforks/45000000''`
    operationId: hafbe_endpoints.get_hardfork_at_block
    parameters:
      - in: path
        name: block-num
        required: true
        schema:
          type: integer
        description: Block number, from 1 up to the last block this API has processed.
    responses:
      '200':
        description: The hardfork in force at that block.
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hafbe_backend.hardfork'
            example:
              hardfork_num: 23
              block_num: 41818752
              timestamp: '2020-03-20T14:00:00'
      '400':
        description: The block number is below 1 or above the last processed block.
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_hardfork_at_block;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_hardfork_at_block(
    "block-num" INT
)
RETURNS hafbe_backend.hardfork
-- openapi-generated-code-end
LANGUAGE plpgsql STABLE
AS
$$
DECLARE
  _current_block INT := hafbe_backend.get_hafbe_head_block();
BEGIN
  IF "block-num" IS NULL OR "block-num" < 1 THEN
    RAISE EXCEPTION 'Block_num ''%'' must be 1 or greater.', COALESCE("block-num"::TEXT, 'NULL');
  END IF;
  PERFORM hafbe_backend.validate_block_num_too_high("block-num", _current_block);

  -- The era of an irreversible block cannot change; any later block can still be forked out.
  IF "block-num" <= hive.app_get_irreversible_block('hafbe_app') THEN
    PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=31536000"}]', true);
  ELSE
    PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);
  END IF;

  RETURN hafbe_backend.get_hardfork_at_block("block-num");
END
$$;

RESET ROLE;
