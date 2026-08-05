SET ROLE hafbe_owner;

/** openapi:paths
/transaction-statistics:
  get:
    tags:
      - Transactions
    summary: Aggregated transaction statistics
    description: |
      History of amount of transactions per day, month or year.

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_transaction_statistics();`

      REST call example
      * `GET ''https://%1$s/hafbe-api/transaction-statistics''`
    operationId: hafbe_endpoints.get_transaction_statistics
    parameters:
      - in: query
        name: granularity
        required: false
        schema:
          $ref: '#/components/schemas/hafbe_backend.granularity'
          default: yearly
        description: |
          granularity types:

          * daily

          * monthly

          * yearly
      - in: query
        name: direction
        required: false
        schema:
          $ref: '#/components/schemas/hafbe_backend.sort_direction'
          default: desc
        description: |
          Sort order:

           * `asc` - Ascending, from oldest to newest 

           * `desc` - Descending, from newest to oldest 
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
          Every period in the requested range, as a flat array.

          * Returns array of `hafbe_backend.transaction_stats`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hafbe_backend.array_of_transaction_stats'
            example: [
              {
                "date": "2017-01-01T00:00:00",
                "trx_count": 6961192,
                "avg_trx": 1,
                "min_trx": 0,
                "max_trx": 89,
                "last_block_num": 5000000
              }
            ]

 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_transaction_statistics;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_transaction_statistics(
    "granularity" hafbe_backend.granularity = 'yearly',
    "direction" hafbe_backend.sort_direction = 'desc',
    "from-block" TEXT = NULL,
    "to-block" TEXT = NULL
)
RETURNS SETOF hafbe_backend.transaction_stats 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
SET jit = OFF
AS
$$
DECLARE
  _block_range hive.blocks_range := hive.convert_to_blocks_range("from-block","to-block");
  -- The chain head is read ONCE and used for BOTH the block-num validation and the range
  -- resolution. Two separate reads are two statement snapshots, so during a fork rollback
  -- they can observe different heads (an explicit from-block could pass validation at head
  -- N, then resolve against head N-k and collapse to from > to). STABLE additionally pins
  -- the whole call to one snapshot, matching get_operation_type_statistics.
  _current_block INT             := hafbe_backend.get_hafbe_head_block();
  -- Normalize optional params: an explicit NULL (e.g. {"granularity": null}) must fall back
  -- to the signature default. PostgREST applies the default only when a param is OMITTED,
  -- not when it is explicitly null, so a raw NULL granularity/direction would otherwise
  -- collapse the period series / drop the sort. COALESCE every param with a non-NULL default.
  _granularity    hafbe_backend.granularity    := COALESCE("granularity", 'yearly');
  _direction      hafbe_backend.sort_direction := COALESCE("direction", 'desc');
  _from_ts        TIMESTAMP;
  _to_ts          TIMESTAMP;
BEGIN
  PERFORM hafbe_backend.validate_block_num_too_high(_block_range.first_block, _current_block);

  IF _block_range.last_block <= hive.app_get_irreversible_block() AND _block_range.last_block IS NOT NULL THEN
    PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=31536000"}]', true);
  ELSE
    PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);
  END IF;

  -- Resolve the period-truncated range ONCE, off the single _current_block read above.
  SELECT from_ts, to_ts INTO _from_ts, _to_ts
  FROM hafbe_backend.aggregation_time_range(_granularity, _block_range.first_block, _block_range.last_block, _current_block);

  -- No default window here: one pre-aggregated row per period means even a full-history
  -- daily request is ~3.7k rows / ~400 kB. Only the operation-type histogram, which nests a
  -- per-op-type array in every period, needs bounding (issue #139).
  RETURN QUERY
    SELECT fb.*
    FROM hafbe_backend.get_transaction_aggregation(
      _granularity,
      _from_ts,
      _to_ts
    ) fb
    ORDER BY
      (CASE WHEN _direction = 'desc' THEN fb.date END) DESC,
      (CASE WHEN _direction = 'asc'  THEN fb.date END) ASC;
END
$$;

RESET ROLE;
