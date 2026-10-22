SET ROLE hafbe_owner;

/** openapi:paths
/hardforks:
  get:
    tags:
      - Hardforks
    summary: Hive hardforks with their activation block and time
    description: |
      Lists every hardfork the chain has applied, oldest first, with the block that
      applied it and the timestamp of that block. Only hardforks at or below the last block
      this API has processed are listed.

      Hardfork 0 is the genesis protocol. No hardfork operation applies it, so it is
      reported at block 1.

      The timestamp is the production time of the activation block. It can be later
      than the scheduled hardfork time reported by `database_api.get_hardfork_properties`:
      a hardfork applies only once enough witnesses run it. HF24, scheduled for
      2020-10-06 14:00 UTC, was applied in block 47797680 at 2020-10-14 19:31:24 UTC.

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_hardforks();`

      REST call example
      * `GET ''https://%1$s/hafbe-api/hardforks''`
    operationId: hafbe_endpoints.get_hardforks
    responses:
      '200':
        description: All applied hardforks as a flat array, ordered by hardfork number.
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hafbe_backend.array_of_hardforks'
            example:
              - hardfork_num: 0
                block_num: 1
                timestamp: '2016-03-24T16:05:00'
              - hardfork_num: 1
                block_num: 905693
                timestamp: '2016-04-25T17:30:00'
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_hardforks;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_hardforks()
RETURNS SETOF hafbe_backend.hardfork
-- openapi-generated-code-end
LANGUAGE plpgsql STABLE
AS
$$
BEGIN
  -- A new hardfork can appear at the head, and a reversible one can be undone by a fork.
  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

  RETURN QUERY
    SELECT * FROM hafbe_backend.get_hardforks(hafbe_backend.get_hafbe_head_block());
END
$$;

RESET ROLE;
