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
          Paginated per-period transaction statistics.

          * Returns `hafbe_backend.transaction_stats_return`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hafbe_backend.transaction_stats_return'
            example: {
              "total_periods": 11,
              "total_pages": 1,
              "stats": [
                {
                  "date": "2017-01-01T00:00:00",
                  "trx_count": 6961192,
                  "avg_trx": 1,
                  "min_trx": 0,
                  "max_trx": 89,
                  "last_block_num": 5000000
                }
              ]
            }

      '404':
        description: No such account in the database
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_transaction_statistics;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_transaction_statistics(
    "granularity" hafbe_backend.granularity = 'yearly',
    "direction" hafbe_backend.sort_direction = 'desc',
    "page" INT = 1,
    "page-size" INT = 100,
    "from-block" TEXT = NULL,
    "to-block" TEXT = NULL
)
RETURNS hafbe_backend.transaction_stats_return
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
  _from_ts        TIMESTAMP;
  _to_ts          TIMESTAMP;
  _result         hafbe_backend.transaction_stats[];
BEGIN
  PERFORM hafbe_backend.validate_block_num_too_high(_block_range.first_block, _current_block);
  PERFORM hafbe_backend.validate_limit(_page_size, 1000);
  PERFORM hafbe_backend.validate_negative_limit(_page_size);
  PERFORM hafbe_backend.validate_negative_page(_page);

  IF _block_range.last_block <= hive.app_get_irreversible_block() AND _block_range.last_block IS NOT NULL THEN
    PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=31536000"}]', true);
  ELSE
    PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);
  END IF;

  -- Resolve the full period-truncated range ONCE (off the single _current_block read above),
  -- then share the window with both the period count (total_pages) and the paged aggregation,
  -- so they can never disagree and the range is resolved a single time.
  SELECT from_ts, to_ts INTO _from_ts, _to_ts
  FROM hafbe_backend.aggregation_time_range(_granularity, _block_range.first_block, _block_range.last_block, _current_block);

  _total_periods := hafbe_backend.aggregation_period_count(_granularity, _from_ts, _to_ts);
  _total_pages   := hafah_backend.total_pages(_total_periods, _page_size);

  PERFORM hafbe_backend.validate_page(_page, _total_pages);

  _result := ARRAY(
    SELECT fb::hafbe_backend.transaction_stats
    FROM hafbe_backend.get_transaction_aggregation(
      _granularity,
      _direction,
      _from_ts,
      _to_ts,
      _page,
      _page_size
    ) fb
    ORDER BY
      (CASE WHEN _direction = 'desc' THEN fb.date END) DESC,
      (CASE WHEN _direction = 'asc'  THEN fb.date END) ASC
  );

  RETURN (
    COALESCE(_total_periods, 0),
    COALESCE(_total_pages, 0),
    COALESCE(_result, '{}'::hafbe_backend.transaction_stats[])
  )::hafbe_backend.transaction_stats_return;

END
$$;

RESET ROLE;
