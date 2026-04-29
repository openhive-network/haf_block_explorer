SET ROLE hafbe_owner;

/** openapi:paths
/total_wallet_addresses:
  get:
    tags:
      - Accounts
    summary: Total wallet counts over time
    description: |
      Time-series of new wallets (accounts) created per day, month or year,
      plus the cumulative total wallet count on the chain at the end of each period.

      Useful for live wallet-count tickers and chain-growth charts.

      The latest period (today''s partial day, current month, current year) is
      always included; its `date` is capped at the current timestamp rather than
      the period-end boundary.

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_total_wallet_addresses();`

      REST call example
      * `GET ''https://%1$s/hafbe-api/total_wallet_addresses''`
    operationId: hafbe_endpoints.get_total_wallet_addresses
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
          Lower limit of the block range: block-number (integer) or timestamp (YYYY-MM-DD HH:MI:SS).

          * `2016-09-15 19:47:21`

          * `5000000`
      - in: query
        name: to-block
        required: false
        schema:
          type: string
          default: NULL
        description: |
          Upper limit of the block range: block-number (integer) or timestamp (YYYY-MM-DD HH:MI:SS).

          * `2016-09-15 19:47:21`

          * `5000000`
    responses:
      '200':
        description: |
          Wallet-count statistics over time

          * Returns array of `hafbe_backend.wallet_stats`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hafbe_backend.array_of_wallet_stats'
            example: [
              {
                "date": "2017-01-01T00:00:00",
                "new_wallets": 12345,
                "total_wallets": 234567
              }
            ]
      '400':
        description: Invalid block range or parameter
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_total_wallet_addresses;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_total_wallet_addresses(
    "granularity" hafbe_backend.granularity = 'yearly',
    "direction" hafbe_backend.sort_direction = 'desc',
    "from-block" TEXT = NULL,
    "to-block" TEXT = NULL
)
RETURNS SETOF hafbe_backend.wallet_stats 
-- openapi-generated-code-end
LANGUAGE 'plpgsql'
SET jit = OFF
AS
$$
DECLARE
  _block_range    hive.blocks_range := hive.convert_to_blocks_range("from-block", "to-block");
  _head_block_num INT               := hafbe_backend.get_hafbe_head_block();
BEGIN
  PERFORM hafbe_backend.validate_block_num_too_high(_block_range.first_block, _head_block_num);

  IF _block_range.last_block <= hive.app_get_irreversible_block() AND _block_range.last_block IS NOT NULL THEN
    PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=31536000"}]', true);
  ELSE
    PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);
  END IF;

  RETURN QUERY
    SELECT fb.date, fb.new_wallets, fb.total_wallets
    FROM hafbe_backend.get_total_wallet_address_aggregation(
      "granularity",
      "direction",
      _block_range.first_block,
      _block_range.last_block
    ) fb;
END
$$;

RESET ROLE;
