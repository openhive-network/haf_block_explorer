SET ROLE hafbe_owner;

-- Witness page endpoint
/** openapi:paths
/witnesses/{account-name}/votes/history:
  get:
    tags:
      - Witnesses
    summary: Get the history of votes for this witness.
    description: |
      Get information about each vote cast for this witness

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_witness_votes_history(''blocktrades'');`
      
      REST call example
      * `GET ''https://%1$s/hafbe-api/witnesses/blocktrades/votes/history?result-limit=2''`
    operationId: hafbe_endpoints.get_witness_votes_history
    parameters:
      - in: path
        name: account-name
        required: true
        schema:
          type: string
        description: witness account name
      - in: query
        name: sort
        required: false
        schema:
          $ref: '#/components/schemas/hafbe_types.order_by_votes'
          default: timestamp
        description: |
          Sort order:

           * `voter` - account name of voter

           * `vests` - total voting power = account_vests + proxied_vests of voter

           * `account_vests` - direct vests of voter

           * `proxied_vests` - proxied vests of voter

           * `timestamp` - time when user performed vote/unvote operation
      - in: query
        name: direction
        required: false
        schema:
          $ref: '#/components/schemas/hafbe_types.sort_direction'
          default: desc
      - in: query
        name: result-limit
        required: false
        schema:
          type: integer
          default: 100
        description: Return at most `result-limit` voters
        description: |
          Sort order:

           * `asc` - Ascending, from A to Z or smallest to largest

           * `desc` - Descending, from Z to A or largest to smallest
      - in: query
        name: from-block
        required: false
        schema:
          type: string
          default: NULL
        description: |
          Lower limit of the block range, can be represented either by a block-number (integer) or a timestamp (in the format YYYY-MM-DD HH:MI:SS).

          The provided `timestamp` will be converted to a `block-num` by finding the first block 
          where the block''s `created_at` is more than or equal to the given `timestamp` (i.e. `block''s created_at >= timestamp`).

          The function will interpret and convert the input based on its format, example input:

          * `2016-09-15 19:47:21`

          * `5000000`
      - in: query
        name: to-block
        required: false
        schema:
          type: string
          default: NULL
        description: | 
          Similar to the from-block parameter, can either be a block-number (integer) or a timestamp (formatted as YYYY-MM-DD HH:MI:SS). 

          The provided `timestamp` will be converted to a `block-num` by finding the first block 
          where the block''s `created_at` is less than or equal to the given `timestamp` (i.e. `block''s created_at <= timestamp`).
          
          The function will convert the value depending on its format, example input:

          * `2016-09-15 19:47:21`

          * `5000000`
    responses:
      '200':
        description: |
          The number of voters currently voting for this witness

          * Returns `hafbe_types.witness_votes_history`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hafbe_types.witness_votes_history'
            example: {
              "votes_updated_at": "2024-08-29T12:05:08.097875",
              "votes_history": [
                {
                  "voter_name": "jeremyfromwi",
                  "approve": true,
                  "vests": "441156952466",
                  "account_vests": "441156952466",
                  "proxied_vests": "0",
                  "timestamp": "2016-09-15T07:07:15"
                },
                {
                  "voter_name": "cryptomental",
                  "approve": true,
                  "vests": "686005633844",
                  "account_vests": "686005633844",
                  "proxied_vests": "0",
                  "timestamp": "2016-09-15T07:00:51"
                }
              ]
            }
      '404':
        description: No such witness
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_witness_votes_history;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_witness_votes_history(
    "account-name" TEXT,
    "sort" hafbe_types.order_by_votes = 'timestamp',
    "direction" hafbe_types.sort_direction = 'desc',
    "result-limit" INT = 100,
    "from-block" TEXT = NULL,
    "to-block" TEXT = NULL
)
RETURNS hafbe_types.witness_votes_history 
-- openapi-generated-code-end
LANGUAGE 'plpgsql'
STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
AS
$$
DECLARE 
  _block_range hive.blocks_range := hive.convert_to_blocks_range("from-block","to-block");
  _hafbe_current_block INT := (SELECT current_block_num FROM hafd.contexts WHERE name = 'hafbe_app');
  _witness_id INT = hafbe_backend.get_account_id("account-name");
  _votes_updated_at TIMESTAMP;

  _result hafbe_types.witness_votes_history_record[];
BEGIN
  PERFORM hafbe_exceptions.validate_limit("result-limit", 10000, 'result-limit');
  PERFORM hafbe_exceptions.validate_negative_limit("result-limit",'result-limit');
  PERFORM hafbe_exceptions.validate_negative_page("result-limit");

  IF _block_range.first_block IS NOT NULL AND _hafbe_current_block < _block_range.first_block THEN
    PERFORM hafbe_exceptions.raise_block_num_too_high_exception(_block_range.first_block::NUMERIC, _hafbe_current_block);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM hafbe_app.current_witnesses WHERE witness_id = _witness_id) THEN
    PERFORM hafbe_exceptions.rest_raise_missing_witness("account-name");
  END IF;

  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

  _votes_updated_at := (
    SELECT last_updated_at 
    FROM hafbe_app.witnesses_cache_config
  );

  _result := array_agg(row) FROM (
    SELECT 
      ba.voter_name,
      ba.approve,
      ba.vests,
      ba.account_vests,
      ba.proxied_vests,
      ba.timestamp
    FROM hafbe_backend.get_witness_votes_history(
      "account-name",
      "sort",
      "direction",
      "result-limit",
      _block_range.first_block,
      _block_range.last_block
    ) ba
  ) row;

  RETURN (
    COALESCE(_votes_updated_at, '1970-01-01T00:00:00'),
    COALESCE(_result, '{}'::hafbe_types.witness_votes_history_record[])
  )::hafbe_types.witness_votes_history;

END
$$;

RESET ROLE;
