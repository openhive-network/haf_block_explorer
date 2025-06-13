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
      * `GET ''https://%1$s/hafbe-api/witnesses/blocktrades/votes/history?page-size=2''`
    operationId: hafbe_endpoints.get_witness_votes_history
    parameters:
      - in: path
        name: account-name
        required: true
        schema:
          type: string
        description: witness account name
      - in: query
        name: voter-name
        required: false
        schema:
          type: string
          default: NULL
        description: |
          When provided, only votes associated with this account will be included in the results, 
          allowing for targeted analysis of an individual account''s voting activity.
      - in: query
        name: page
        required: false
        schema:
          type: integer
          default: 1
        description: |
          Return page on `page` number, defaults to `1`
      - in: query
        name: page-size
        required: false
        schema:
          type: integer
          default: 100
        description: Return max `page-size` operations per page, defaults to `100`
      - in: query
        name: direction
        required: false
        schema:
          $ref: '#/components/schemas/hafbe_types.sort_direction'
          default: desc
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
              "total_votes": 263,
              "total_pages": 132,
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
    "voter-name" TEXT = NULL,
    "page" INT = 1,
    "page-size" INT = 100,
    "direction" hafbe_types.sort_direction = 'desc',
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
  _filter_account_id INT = hafbe_backend.get_account_id("voter-name");
  _ops_count INT;
  __total_pages INT;

  _result hafbe_types.witness_votes_history_record[];
BEGIN
  PERFORM hafbe_exceptions.validate_limit("page-size", 10000);
  PERFORM hafbe_exceptions.validate_negative_limit("page-size");
  PERFORM hafbe_exceptions.validate_negative_page("page");

  IF _block_range.first_block IS NOT NULL AND _hafbe_current_block < _block_range.first_block THEN
    PERFORM hafbe_exceptions.raise_block_num_too_high_exception(_block_range.first_block::NUMERIC, _hafbe_current_block);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM hafbe_app.current_witnesses WHERE witness_id = _witness_id) THEN
    PERFORM hafbe_exceptions.rest_raise_missing_witness("account-name");
  END IF;

  IF "voter-name" IS NOT NULL AND _filter_account_id IS NULL THEN
    PERFORM hafbe_exceptions.rest_raise_missing_account("voter-name");
  END IF;

  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

  _ops_count := (
    SELECT COUNT(*) 
    FROM hafbe_app.witness_votes_history 
    WHERE 
      witness_id = _witness_id AND
      (_block_range.first_block IS NULL OR source_op_block >= _block_range.first_block) AND
      (_block_range.last_block IS NULL OR source_op_block <= _block_range.last_block) AND
      (_filter_account_id IS NULL OR voter_id = _filter_account_id)
  );

  __total_pages := (
    CASE 
      WHEN (_ops_count % "page-size") = 0 THEN 
        _ops_count/"page-size" 
      ELSE 
        (_ops_count/"page-size") + 1
    END
  );

  PERFORM hafbe_exceptions.validate_page("page", __total_pages);

  _result := array_agg(row) FROM (
    SELECT 
      ba.voter_name,
      ba.approve,
      ba.vests,
      ba.account_vests,
      ba.proxied_vests,
      ba.timestamp
    FROM hafbe_backend.get_witness_votes_history(
      _witness_id,
      _filter_account_id,
      "page",
      "page-size",
      "direction",
      _block_range.first_block,
      _block_range.last_block
    ) ba
  ) row;

  RETURN (
    COALESCE(_ops_count,0),
    COALESCE(__total_pages,0),
    COALESCE(_result, '{}'::hafbe_types.witness_votes_history_record[])
  )::hafbe_types.witness_votes_history;

END
$$;

RESET ROLE;
