SET ROLE hafbe_owner;

/** openapi:paths
/hbd/status:
  get:
    tags:
      - HBD
    summary: HBD supply and interest rate history
    description: |
      Returns the HBD state at the last processed block of each UTC period.
      Uses the existing transaction statistics to select blocks. Weekly periods start on Monday.
      Range boundaries select whole periods, as in transaction statistics.
      Periods without blocks retain the last available state.

      The debt ratio uses the provisional formula from issue 147 while its definition is clarified.

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_hbd_status();`

      REST call example
      * `GET ''https://%1$s/hafbe-api/hbd/status''`
    operationId: hafbe_endpoints.get_hbd_status
    parameters:
      - in: query
        name: granularity
        required: false
        schema:
          $ref: '#/components/schemas/hafbe_backend.hbd_granularity'
          default: yearly
        description: Period size; daily, weekly, monthly or yearly.
      - in: query
        name: direction
        required: false
        schema:
          $ref: '#/components/schemas/hafbe_backend.sort_direction'
          default: desc
        description: Sort periods from oldest to newest (asc) or newest to oldest (desc).
      - in: query
        name: from-block
        required: false
        schema:
          type: string
          default: NULL
        description: >-
          Lower block boundary, supplied as a block number or timestamp, using the shared HAF
          block-range conversion. The containing calendar period is included in full.
          Omitted or null means the beginning of the processed history.
      - in: query
        name: to-block
        required: false
        schema:
          type: string
          default: NULL
        description: >-
          Upper block boundary, supplied as a block number or timestamp, using the shared HAF
          block-range conversion. The containing calendar period is included in full, up to
          the processed application head. Omitted or null means the processed head.
    responses:
      '200':
        description: All periods in the requested range as a flat array, without pagination.
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hafbe_backend.array_of_hbd_status'
      '400':
        description: Invalid granularity, direction or block range.
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_hbd_status;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_hbd_status(
    "granularity" hafbe_backend.hbd_granularity = 'yearly',
    "direction" hafbe_backend.sort_direction = 'desc',
    "from-block" TEXT = NULL,
    "to-block" TEXT = NULL
)
RETURNS SETOF hafbe_backend.hbd_status
-- openapi-generated-code-end
LANGUAGE plpgsql STABLE
SET jit = OFF
SET TimeZone = 'UTC'
AS
$$
DECLARE
  _block_range   hive.blocks_range := hive.convert_to_blocks_range("from-block", "to-block");
  _current_block INT := hafbe_backend.get_hafbe_head_block();
  _granularity   hafbe_backend.hbd_granularity := COALESCE("granularity", 'yearly');
  _direction     hafbe_backend.sort_direction := COALESCE("direction", 'desc');
BEGIN
  PERFORM hafbe_backend.validate_block_num_too_high(_block_range.first_block, _current_block);

  -- Keep even historical responses short-lived while the issue's formula is provisional.
  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

  RETURN QUERY
    SELECT
      ab.date,
      bv.current_hbd_supply::BIGINT,
      bv.virtual_supply::BIGINT,
      -- TODO(#147): replace the provisional issue formula after the author clarifies the metric.
      100::NUMERIC * bv.current_hbd_supply / NULLIF(bv.virtual_supply, 0),
      bv.hbd_interest_rate::INT
    FROM hafbe_backend.get_aggregation_blocks(
      _granularity, _direction, _block_range.first_block, _block_range.last_block, _current_block
    ) ab
    -- Keep each view lookup tied to one selected block; avoid joining the entire history.
    JOIN LATERAL (
      SELECT b.current_hbd_supply, b.virtual_supply, b.hbd_interest_rate
      FROM hafbe_app.blocks_view b
      WHERE b.num = ab.last_block_num AND b.num <= _current_block
      LIMIT 1
    ) bv ON TRUE
    ORDER BY
      (CASE WHEN _direction = 'desc' THEN ab.date END) DESC,
      (CASE WHEN _direction = 'asc' THEN ab.date END) ASC;
END
$$;

RESET ROLE;
