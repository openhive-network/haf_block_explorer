SET ROLE hafbe_owner;

/** openapi:components:schemas
hafbe_types.block_raw:
  type: object
  properties:
    previous:
      type: string
      x-sql-datatype: bytea
      description: hash of a previous block
    timestamp:
      type: string
      format: date-time
      description: the timestamp when the block was created
    witness:
      type: string
      x-sql-datatype: VARCHAR
      description: account name of block's producer
    transaction_merkle_root:
      type: string
      x-sql-datatype: bytea
      description: >-
        single hash representing the combined hashes of all transactions in a block
    extensions:
      type: string
      x-sql-datatype: JSONB
      description: >-
        various additional data/parameters related to the subject at hand.
        Most often, there's nothing specific, but it's a mechanism for extending various functionalities
        where something might appear in the future.
    witness_signature:
      type: string
      x-sql-datatype: bytea
      description: witness signature
    transactions:
      type: string
      x-sql-datatype: JSONB
      description: list of transactions
    block_id:
      type: string
      x-sql-datatype: bytea
      description: the block_id from the block header
    signing_key:
      type: string
      description: >-
        it refers to the public key of the witness used for signing blocks and other witness operations
    transaction_ids:
      type: array
      items:
        type: string
      x-sql-datatype: bytea[]
      description: list of transaction's hashes that occured in given block
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_types.block_raw CASCADE;
CREATE TYPE hafbe_types.block_raw AS (
    "previous" bytea,
    "timestamp" TIMESTAMP,
    "witness" VARCHAR,
    "transaction_merkle_root" bytea,
    "extensions" JSONB,
    "witness_signature" bytea,
    "transactions" JSONB,
    "block_id" bytea,
    "signing_key" TEXT,
    "transaction_ids" bytea[]
);
-- openapi-generated-code-end


RESET ROLE;
