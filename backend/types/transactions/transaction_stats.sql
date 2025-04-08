SET ROLE hafbe_owner;

/** openapi:components:schemas
hafbe_types.transaction_stats:
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
DROP TYPE IF EXISTS hafbe_types.transaction_stats CASCADE;
CREATE TYPE hafbe_types.transaction_stats AS (
    "date" TIMESTAMP,
    "trx_count" INT,
    "avg_trx" INT,
    "min_trx" INT,
    "max_trx" INT,
    "last_block_num" INT
);
-- openapi-generated-code-end

/** openapi:components:schemas
hafbe_types.array_of_transaction_stats:
  type: array
  items:
    $ref: '#/components/schemas/hafbe_types.transaction_stats'
*/

RESET ROLE;
