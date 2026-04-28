SET ROLE hafbe_owner;

-- Proposal page endpoint
/** openapi:paths
/proposals/{proposal-id}/votes/history:
  get:
    tags:
      - Proposals
    summary: Get the history of votes cast for this proposal.
    description: |
      Get information about each vote cast for this proposal, including
      approvals and later withdrawals of approval.

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_proposal_votes_history(1);`

      REST call example
      * `GET ''https://%1$s/hafbe-api/proposals/1/votes/history?page-size=2''`
    operationId: hafbe_endpoints.get_proposal_votes_history
    parameters:
      - in: path
        name: proposal-id
        required: true
        schema:
          type: integer
        description: proposal id
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
          $ref: '#/components/schemas/hafbe_backend.sort_direction'
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
          The history of votes cast for this proposal

          * Returns `hafbe_backend.proposal_votes_history`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hafbe_backend.proposal_votes_history'
            example: {
              "total_votes": 12,
              "total_pages": 6,
              "votes_history": [
                {
                  "voter_name": "alice",
                  "approve": true,
                  "timestamp": "2019-11-05T10:12:09"
                },
                {
                  "voter_name": "bob",
                  "approve": false,
                  "timestamp": "2019-11-04T08:43:21"
                }
              ]
            }
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_proposal_votes_history;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_proposal_votes_history(
    "proposal-id" INT,
    "voter-name" TEXT = NULL,
    "page" INT = 1,
    "page-size" INT = 100,
    "direction" hafbe_backend.sort_direction = 'desc',
    "from-block" TEXT = NULL,
    "to-block" TEXT = NULL
)
RETURNS hafbe_backend.proposal_votes_history 
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
  _head_block_num INT            := hafbe_backend.get_hafbe_head_block();
  _filter_account_id INT         := hafah_backend.get_account_id("voter-name", FALSE);
  _ops_count INT;
  _total_pages INT;

  _result hafbe_backend.proposal_votes_history_record[];
BEGIN
  PERFORM hafbe_backend.validate_limit("page-size", 10000);
  PERFORM hafbe_backend.validate_negative_limit("page-size");
  PERFORM hafbe_backend.validate_negative_page("page");
  PERFORM hafbe_backend.validate_block_num_too_high(_block_range.first_block, _head_block_num);

  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

  _ops_count   := hafbe_backend.get_proposal_votes_history_count("proposal-id", _filter_account_id, _block_range);
  _total_pages := hafah_backend.total_pages(_ops_count, "page-size");

  PERFORM hafbe_backend.validate_page("page", _total_pages);

  _result := array_agg(row) FROM (
    SELECT
      ba.voter_name,
      ba.approve,
      ba.timestamp
    FROM hafbe_backend.get_proposal_votes_history(
      "proposal-id",
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
    COALESCE(_total_pages,0),
    COALESCE(_result, '{}'::hafbe_backend.proposal_votes_history_record[])
  )::hafbe_backend.proposal_votes_history;

END
$$;

RESET ROLE;
