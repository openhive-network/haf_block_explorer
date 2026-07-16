SET ROLE hafbe_owner;

-- Active proposal votes endpoint
/** openapi:paths
/proposals/votes:
  get:
    tags:
      - Proposals
    summary: List current active proposal votes
    description: |
      List currently active approvals across all proposals. The status filter
      applies to the joined proposal, not the vote. `voter_vests` is reported
      as 0 for voters who currently have a governance proxy set (their stake
      counts through the proxy, not through their direct vote).

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_proposal_votes();`

      REST call example
      * `GET ''https://%1$s/hafbe-api/proposals/votes?sort=by_proposal_voter&status=votable''`
    operationId: hafbe_endpoints.get_proposal_votes
    parameters:
      - in: query
        name: page
        required: false
        schema:
          type: integer
          default: 1
          minimum: 1
        description: |
          Return page on `page` number, defaults to `1`
      - in: query
        name: page-size
        required: false
        schema:
          type: integer
          default: 100
          minimum: 1
          maximum: 1000
        description: Return max `page-size` votes per page, defaults to `100`
      - in: query
        name: sort
        required: false
        schema:
          $ref: '#/components/schemas/hafbe_backend.order_by_proposal_vote'
          default: by_proposal_voter
        description: |
          Sort key:

           * `by_voter_proposal` - sort by (voter, then proposal_id)

           * `by_proposal_voter` - sort by (proposal_id, then voter)
      - in: query
        name: direction
        required: false
        schema:
          $ref: '#/components/schemas/hafbe_backend.sort_direction'
          default: asc
      - in: query
        name: status
        required: false
        schema:
          $ref: '#/components/schemas/hafbe_backend.proposal_status'
          default: all
        description: Filter votes by the joined proposal''s status (removed proposals are never returned).
      - in: query
        name: proposal-id
        required: false
        schema:
          type: integer
          default: NULL
        description: Filter votes for a specific proposal ID
      - in: query
        name: voter
        required: false
        schema:
          type: string
          default: NULL
        description: Filter votes cast by a specific voter account name
    responses:
      '200':
        description: |
          The list of active proposal votes

          * Returns `hafbe_backend.proposal_votes_return`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hafbe_backend.proposal_votes_return'
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_proposal_votes;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_proposal_votes(
    "page" INT = 1,
    "page-size" INT = 100,
    "sort" hafbe_backend.order_by_proposal_vote = 'by_proposal_voter',
    "direction" hafbe_backend.sort_direction = 'asc',
    "status" hafbe_backend.proposal_status = 'all',
    "proposal-id" INT = NULL,
    "voter" TEXT = NULL
)
RETURNS hafbe_backend.proposal_votes_return 
-- openapi-generated-code-end
LANGUAGE 'plpgsql'
STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
AS
$$
DECLARE
  _ops_count   INT;
  _total_pages INT;
  _result      hafbe_backend.proposal_vote[];
  _voter_id    INT := hafah_backend.get_account_id("voter", FALSE);
  _page        INT := COALESCE("page", 1);
  _page_size   INT := COALESCE("page-size", 100);
  _sort        hafbe_backend.order_by_proposal_vote := COALESCE("sort", 'by_proposal_voter');
  _direction   hafbe_backend.sort_direction := COALESCE("direction", 'asc');
  _status      hafbe_backend.proposal_status := COALESCE("status", 'all');
BEGIN
  PERFORM hafbe_backend.validate_limit(_page_size, 1000);
  PERFORM hafbe_backend.validate_negative_limit(_page_size);
  PERFORM hafbe_backend.validate_negative_page(_page);

  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

  _ops_count   := hafbe_backend.get_proposal_votes_count(_status, "proposal-id", _voter_id);
  _total_pages := hafah_backend.total_pages(_ops_count, _page_size);

  PERFORM hafbe_backend.validate_page(_page, _total_pages);

  _result := array_agg(row) FROM (
    SELECT
      ba.voter_name,
      ba.proposal,
      ba.voter_vests,
      ba.direct_vests,
      ba.proxied_vests,
      ba.proxy,
      ba.timestamp
    FROM hafbe_backend.get_proposal_votes(
      _status,
      _page,
      _page_size,
      _sort,
      _direction,
      "proposal-id",
      _voter_id
    ) ba
  ) row;

  RETURN (
    COALESCE(_ops_count,0),
    COALESCE(_total_pages,0),
    COALESCE(_result, '{}'::hafbe_backend.proposal_vote[])
  )::hafbe_backend.proposal_votes_return;

END
$$;

RESET ROLE;
