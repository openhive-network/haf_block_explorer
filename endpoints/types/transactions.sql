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

/** openapi:components:schemas
hafbe_backend.transaction_stats_return:
  type: object
  properties:
    total_periods:
      type: integer
      description: total number of periods in the requested range (across all pages)
    total_pages:
      type: integer
      description: total number of pages for the requested page-size
    stats:
      type: array
      items:
        $ref: '#/components/schemas/hafbe_backend.transaction_stats'
      description: the requested page of per-period transaction statistics
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.transaction_stats_return CASCADE;
CREATE TYPE hafbe_backend.transaction_stats_return AS (
    "total_periods" INT,
    "total_pages" INT,
    "stats" hafbe_backend.transaction_stats[]
);
-- openapi-generated-code-end

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
      description: total number of transactions in the period (from transaction_stats_by_day/month)
    total_operations:
      type: integer
      format: int64
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

/** openapi:components:schemas
hafbe_backend.operation_type_stats_return:
  type: object
  properties:
    total_periods:
      type: integer
      description: total number of periods in the requested range (across all pages)
    total_pages:
      type: integer
      description: total number of pages for the requested page-size
    stats:
      type: array
      items:
        $ref: '#/components/schemas/hafbe_backend.operation_type_stats'
      description: the requested page of per-period operation-type statistics
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.operation_type_stats_return CASCADE;
CREATE TYPE hafbe_backend.operation_type_stats_return AS (
    "total_periods" INT,
    "total_pages" INT,
    "stats" hafbe_backend.operation_type_stats[]
);
-- openapi-generated-code-end

RESET ROLE;
