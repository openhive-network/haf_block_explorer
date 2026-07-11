SET ROLE hafbe_owner;

/** openapi:paths
/operation-type-statistics:
  get:
    tags:
      - Transactions
    summary: Aggregated per-op-type operation counts (with transaction totals)
    description: |
      For each period in the requested block range, returns:

      * `total_transactions` — total transactions in the period (from `transaction_stats_by_day`/`_by_month`)
      * `total_operations`   — total operations in the period (sum of `operations[].op_count`)
      * `operations`         — per-op-type breakdown (`op_type_id`, `op_count`)
      * `last_block_num`     — last block included in the period

      Periods with no data still appear (empty `operations`, totals = 0).

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_operation_type_statistics();`

      REST call example
      * `GET ''https://%1$s/hafbe-api/operation-type-statistics''`
    operationId: hafbe_endpoints.get_operation_type_statistics
    parameters:
      - in: query
        name: granularity
        required: false
        schema:
          $ref: '#/components/schemas/hafbe_backend.granularity'
          default: yearly
        description: |
          Period rollup granularity:

          * `daily`

          * `monthly`

          * `yearly`
      - in: query
        name: direction
        required: false
        schema:
          $ref: '#/components/schemas/hafbe_backend.sort_direction'
          default: desc
        description: |
          Sort order:

          * `asc`  - oldest first

          * `desc` - newest first
      - in: query
        name: page
        required: false
        schema:
          type: integer
          default: 1
          minimum: 1
        description: Page number (1-indexed) of periods to return, in the sorted order.
      - in: query
        name: page-size
        required: false
        schema:
          type: integer
          default: 100
          minimum: 1
          maximum: 1000
        description: Number of periods returned per page (max 1000).
      - in: query
        name: from-block
        required: false
        schema:
          type: string
          default: NULL
        description: |
          Lower bound of the block range. Either a block-number (integer) or a timestamp (`YYYY-MM-DD HH:MI:SS`).

          When a `timestamp` is given, it is converted to the first block whose `created_at >= timestamp`.
      - in: query
        name: to-block
        required: false
        schema:
          type: string
          default: NULL
        description: |
          Upper bound of the block range. Same format as `from-block`.

          When a `timestamp` is given, it is converted to the last block whose `created_at <= timestamp`.
      - in: query
        name: op-types
        required: false
        schema:
          type: string
          default: NULL
        description: |
          Comma-separated list of `op_type_id` values to include (e.g. `0,1,18`).
          When omitted, every operation type that occurs in the period is returned.

          Note: when this filter is set, `total_operations` reflects the sum of the
          filtered op types only. `total_transactions` is always the unfiltered
          period total (transactions, not operations, so a filter on op types
          does not apply to it).
    responses:
      '200':
        description: |
          Paginated per-period operation-type histogram with transaction totals.

          * Returns `hafbe_backend.operation_type_stats_return`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hafbe_backend.operation_type_stats_return'
            example: {
              "total_periods": 3752,
              "total_pages": 38,
              "stats": [
                {
                  "date": "2017-01-02T00:00:00",
                  "total_transactions": 412000,
                  "total_operations": 365000,
                  "operations": [
                    {"op_type_id": 0,  "op_count": 98000},
                    {"op_type_id": 1,  "op_count": 45000},
                    {"op_type_id": 18, "op_count": 210000}
                  ],
                  "last_block_num": 5000000
                }
              ]
            }
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_operation_type_statistics;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_operation_type_statistics(
    "granularity" hafbe_backend.granularity = 'yearly',
    "direction" hafbe_backend.sort_direction = 'desc',
    "page" INT = 1,
    "page-size" INT = 100,
    "from-block" TEXT = NULL,
    "to-block" TEXT = NULL,
    "op-types" TEXT = NULL
)
RETURNS hafbe_backend.operation_type_stats_return
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
SET jit = OFF
AS
$$
DECLARE
  _block_range    hive.blocks_range := hive.convert_to_blocks_range("from-block","to-block");
  _head_block_num INT               := hafbe_backend.get_hafbe_head_block();
  _op_types       INT[]             := NULL;
  -- Normalize optional params: an explicit NULL (e.g. {"page-size": null} or
  -- {"granularity": null}) must fall back to the signature default. PostgREST applies the
  -- default only when a param is OMITTED, not when it is explicitly null, so a raw NULL
  -- otherwise slips past the validators (NULL > 1000 / NULL <= 0 are NULL, not TRUE) into
  -- LIMIT NULL (= "no limit"), and a NULL granularity/direction collapses the period series
  -- / drops the sort. COALESCE every param that has a non-NULL default.
  _granularity    hafbe_backend.granularity    := COALESCE("granularity", 'yearly');
  _direction      hafbe_backend.sort_direction := COALESCE("direction", 'desc');
  _page           INT               := COALESCE("page", 1);
  _page_size      INT               := COALESCE("page-size", 100);
  _total_periods  INT;
  _total_pages    INT;
  _current_block  INT;
  _from_ts        TIMESTAMP;
  _to_ts          TIMESTAMP;
  _result         hafbe_backend.operation_type_stats[];
BEGIN
  PERFORM hafbe_backend.validate_block_num_too_high(_block_range.first_block, _head_block_num);
  PERFORM hafbe_backend.validate_limit(_page_size, 1000);
  PERFORM hafbe_backend.validate_negative_limit(_page_size);
  PERFORM hafbe_backend.validate_negative_page(_page);

  -- Parse op-types CSV (e.g. "0,1,18") into INT[]. NULL or empty -> no filter.
  IF "op-types" IS NOT NULL AND length(trim("op-types")) > 0 THEN
    BEGIN
      _op_types := string_to_array("op-types", ',')::INT[];
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION 'Invalid op-types parameter: expected comma-separated integers, got "%"', "op-types"
        USING ERRCODE = '22023';
    END;
  END IF;

  IF _block_range.last_block <= hive.app_get_irreversible_block() AND _block_range.last_block IS NOT NULL THEN
    PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=31536000"}]', true);
  ELSE
    PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);
  END IF;

  -- Resolve current_block + the full period-truncated range ONCE, then share the window
  -- with both the period count (total_pages) and the paged aggregation, so they can never
  -- disagree (e.g. a block committed mid-request) and the range is resolved a single time.
  _current_block := (SELECT current_block_num FROM hafd.contexts WHERE name = 'hafbe_app');
  SELECT from_ts, to_ts INTO _from_ts, _to_ts
  FROM hafbe_backend.aggregation_time_range(_granularity, _block_range.first_block, _block_range.last_block, _current_block);

  _total_periods := hafbe_backend.aggregation_period_count(_granularity, _from_ts, _to_ts);
  _total_pages   := hafah_backend.total_pages(_total_periods, _page_size);

  PERFORM hafbe_backend.validate_page(_page, _total_pages);

  _result := ARRAY(
    SELECT a::hafbe_backend.operation_type_stats
    FROM hafbe_backend.get_operation_type_aggregation(
      _granularity,
      _direction,
      _from_ts,
      _to_ts,
      _page,
      _page_size,
      _op_types
    ) a
    ORDER BY
      (CASE WHEN _direction = 'desc' THEN a.date END) DESC,
      (CASE WHEN _direction = 'asc'  THEN a.date END) ASC
  );

  RETURN (
    COALESCE(_total_periods, 0),
    COALESCE(_total_pages, 0),
    COALESCE(_result, '{}'::hafbe_backend.operation_type_stats[])
  )::hafbe_backend.operation_type_stats_return;
END
$$;

RESET ROLE;
