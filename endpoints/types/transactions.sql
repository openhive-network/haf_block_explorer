SET ROLE hafbe_owner;

-- Transaction-related types for hafbe_backend

----------------------------------------------------------------------

/** openapi:components:schemas
hafbe_backend.transaction_stats:
  type: object
  properties:
    date:
      type: string
      format: date-time
      description: the time transaction was included in the blockchain
    trx_count:
      type: integer
      description: amount of transactions
    avg_trx:
      type: integer
      description: avarage amount of transactions in block
    min_trx:
      type: integer
      description: minimal amount of transactions in block
    max_trx:
      type: integer
      description: maximum amount of transactions in block
    last_block_num:
      type: integer
      description: last block number in time range
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.transaction_stats CASCADE;
CREATE TYPE hafbe_backend.transaction_stats AS (
    "date" TIMESTAMP,
    "trx_count" INT,
    "avg_trx" INT,
    "min_trx" INT,
    "max_trx" INT,
    "last_block_num" INT
);
-- openapi-generated-code-end

/** openapi:components:schemas
hafbe_backend.array_of_transaction_stats:
  type: array
  items:
    $ref: '#/components/schemas/hafbe_backend.transaction_stats'
*/

-- The paginated wrapper type introduced by !494 is intentionally gone: these endpoints feed
-- time-series charts, which draw a whole range at once, so they return a bare array again
-- (see issue #139 / block_explorer_ui#759). This DROP clears the type off databases that
-- already have it; the CASCADE takes the old paginated get_transaction_statistics with it,
-- which is fine because install_app.sh re-creates the endpoint functions after this file.
DROP TYPE IF EXISTS hafbe_backend.transaction_stats_return CASCADE;

----------------------------------------------------------------------

/** openapi:components:schemas
hafbe_backend.period_op_type_count:
  type: object
  properties:
    op_type_id:
      type: integer
      description: operation type identifier
    op_count:
      type: integer
      format: int64
      x-sql-datatype: BIGINT
      description: number of operations of this type in the period
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.period_op_type_count CASCADE;
CREATE TYPE hafbe_backend.period_op_type_count AS (
    "op_type_id" INT,
    "op_count" BIGINT
);
-- openapi-generated-code-end

/** openapi:components:schemas
hafbe_backend.operation_type_stats:
  type: object
  properties:
    date:
      type: string
      format: date-time
      description: end timestamp of the period (capped at current time for the in-progress period)
    total_transactions:
      type: integer
      format: int64
      x-sql-datatype: BIGINT
      description: total number of transactions in the period (from transaction_stats_by_day/month)
    total_operations:
      type: integer
      format: int64
      x-sql-datatype: BIGINT
      description: total number of operations in the period (sum of operations[].op_count)
    operations:
      type: array
      description: per-op-type breakdown for the period
      items:
        $ref: '#/components/schemas/hafbe_backend.period_op_type_count'
    last_block_num:
      type: integer
      description: last block number included in the period
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.operation_type_stats CASCADE;
CREATE TYPE hafbe_backend.operation_type_stats AS (
    "date" TIMESTAMP,
    "total_transactions" BIGINT,
    "total_operations" BIGINT,
    "operations" hafbe_backend.period_op_type_count[],
    "last_block_num" INT
);
-- openapi-generated-code-end

/** openapi:components:schemas
hafbe_backend.array_of_operation_type_stats:
  type: array
  items:
    $ref: '#/components/schemas/hafbe_backend.operation_type_stats'
*/

-- Same as transaction_stats_return above: clears the !494 wrapper off existing databases.
DROP TYPE IF EXISTS hafbe_backend.operation_type_stats_return CASCADE;

RESET ROLE;
