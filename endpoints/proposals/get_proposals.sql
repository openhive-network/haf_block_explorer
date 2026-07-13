SET ROLE hafbe_owner;

-- Proposals list endpoint
/** openapi:paths
/proposals:
  get:
    tags:
      - Proposals
    summary: List current proposals
    description: |
      List proposals with paid amounts and stake-weighted vote totals.
      Sort by `by_total_votes` uses governance VESTS aggregated across direct
      (non-proxied) approvers, matching the hived `list_proposals` ranking.

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_proposals();`

      REST call example
      * `GET ''https://%1$s/hafbe-api/proposals?status=votable&sort=by_total_votes''`
    operationId: hafbe_endpoints.get_proposals
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
        description: Return max `page-size` proposals per page, defaults to `100`
      - in: query
        name: sort
        required: false
        schema:
          $ref: '#/components/schemas/hafbe_backend.order_by_proposal'
          default: by_total_votes
        description: |
          Sort key:

           * `by_creator` - sort alphabetically by creator account

           * `by_start_date` - sort by the proposal''s start_date

           * `by_end_date` - sort by the proposal''s end_date

           * `by_total_votes` - sort by stake-weighted approval (VESTS of direct, non-proxied voters)
      - in: query
        name: direction
        required: false
        schema:
          $ref: '#/components/schemas/hafbe_backend.sort_direction'
          default: desc
        description: |
          Sort order:

           * `asc` - Ascending, from smallest to largest

           * `desc` - Descending, from largest to smallest
      - in: query
        name: status
        required: false
        schema:
          $ref: '#/components/schemas/hafbe_backend.proposal_status'
          default: all
        description: |
          Proposal status filter (removed proposals are never returned):

           * `active` - currently payable (`start_date <= now <= end_date`)

           * `inactive` - not yet started (`now < start_date`)

           * `expired` - finished (`now > end_date`)

           * `votable` - active OR inactive (`now <= end_date`)

           * `all` - any non-removed status
      - in: query
        name: creator
        required: false
        schema:
          type: string
          default: NULL
        description: Filter proposals by creator account name
      - in: query
        name: proposal-ids
        required: false
        schema:
          type: string
          default: NULL
        description: Comma-separated list of proposal IDs to filter by (e.g. `1,2,3`)
      - in: query
        name: voter
        required: false
        schema:
          type: string
          default: NULL
        description: Filter to proposals currently approved by this voter account
      - in: query
        name: search
        required: false
        schema:
          type: string
          default: NULL
        description: Exact-match filter on proposal subject
    responses:
      '200':
        description: |
          The list of proposals

          * Returns `hafbe_backend.proposals_return`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hafbe_backend.proposals_return'
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_proposals;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_proposals(
    "page" INT = 1,
    "page-size" INT = 100,
    "sort" hafbe_backend.order_by_proposal = 'by_total_votes',
    "direction" hafbe_backend.sort_direction = 'desc',
    "status" hafbe_backend.proposal_status = 'all',
    "creator" TEXT = NULL,
    "proposal-ids" TEXT = NULL,
    "voter" TEXT = NULL,
    "search" TEXT = NULL
)
RETURNS hafbe_backend.proposals_return 
-- openapi-generated-code-end
LANGUAGE 'plpgsql'
STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
AS
$$
DECLARE
  _page         INT   := COALESCE("page", 1);
  _page_size    INT   := COALESCE("page-size", 100);
  _sort         hafbe_backend.order_by_proposal := COALESCE("sort", 'by_total_votes');
  _direction    hafbe_backend.sort_direction    := COALESCE("direction", 'desc');
  _status       hafbe_backend.proposal_status   := COALESCE("status", 'all');
  _ops_count    INT;
  _total_pages  INT;
  _result       hafbe_backend.proposal[];
  _creator_id   INT   := hafah_backend.get_account_id("creator", FALSE);
  _voter_id     INT   := hafah_backend.get_account_id("voter",   FALSE);
  _proposal_ids INT[] := CASE
                           WHEN "proposal-ids" IS NULL OR trim("proposal-ids") = '' THEN NULL
                           ELSE (SELECT ARRAY(
                                   SELECT trim(x)::INT
                                   FROM unnest(string_to_array("proposal-ids", ',')) x
                                   WHERE trim(x) <> ''
                                 ))
                         END;
BEGIN
  PERFORM hafbe_backend.validate_limit(_page_size, 1000);
  PERFORM hafbe_backend.validate_negative_limit(_page_size);
  PERFORM hafbe_backend.validate_negative_page(_page);

  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

  _ops_count   := hafbe_backend.get_proposals_count(_status, _creator_id, _proposal_ids, _voter_id, "search");
  _total_pages := hafah_backend.total_pages(_ops_count, _page_size);

  PERFORM hafbe_backend.validate_page(_page, _total_pages);

  _result := array_agg(row) FROM (
    SELECT
      ba.id,
      ba.proposal_id,
      ba.creator,
      ba.receiver,
      ba.start_date,
      ba.end_date,
      ba.daily_pay,
      ba.subject,
      ba.permlink,
      ba.total_votes,
      ba.voters_num,
      ba.paid_amount,
      ba.status
    FROM hafbe_backend.get_proposals(
      _status,
      _page,
      _page_size,
      _sort,
      _direction,
      _creator_id,
      _proposal_ids,
      _voter_id,
      "search"
    ) ba
  ) row;

  RETURN (
    COALESCE(_ops_count,0),
    COALESCE(_total_pages,0),
    COALESCE(_result, '{}'::hafbe_backend.proposal[])
  )::hafbe_backend.proposals_return;

END
$$;

RESET ROLE;
