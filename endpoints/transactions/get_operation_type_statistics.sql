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
          Per-period operation-type histogram with transaction totals.

          * Returns array of `hafbe_backend.operation_type_stats`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hafbe_backend.array_of_operation_type_stats'
            example: [
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
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_operation_type_statistics;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_operation_type_statistics(
    "granularity" hafbe_backend.granularity = 'yearly',
    "direction" hafbe_backend.sort_direction = 'desc',
    "from-block" TEXT = NULL,
    "to-block" TEXT = NULL,
    "op-types" TEXT = NULL
)
RETURNS SETOF hafbe_backend.operation_type_stats 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
SET jit = OFF
AS
$$
DECLARE
  _block_range    hive.blocks_range := hive.convert_to_blocks_range("from-block","to-block");
  _head_block_num INT               := hafbe_backend.get_hafbe_head_block();
  _op_types       INT[]             := NULL;
BEGIN
  PERFORM hafbe_backend.validate_block_num_too_high(_block_range.first_block, _head_block_num);

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

  RETURN QUERY (
    SELECT
      a.date,
      a.total_transactions,
      a.total_operations,
      a.operations,
      a.last_block_num
    FROM hafbe_backend.get_operation_type_aggregation(
      "granularity",
      "direction",
      _block_range.first_block,
      _block_range.last_block,
      _op_types
    ) a
  );
END
$$;

RESET ROLE;
