SET ROLE hafbe_owner;

/** openapi:components:schemas
hafbe_types.block:
  type: object
  properties:
    block_num:
      type: integer
      description: block number
    hash:
      type: string
      x-sql-datatype: bytea
      description: >-
        block hash in a blockchain is a unique, fixed-length string generated 
        by applying a cryptographic hash function to a block's contents
    prev:
      type: string
      x-sql-datatype: bytea
      description: hash of a previous block
    producer_account:
      type: string
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
    signing_key:
      type: string
      description: >-
        it refers to the public key of the witness used for signing blocks and other witness operations
    hbd_interest_rate:
      type: number
      x-sql-datatype: numeric
      description: >-
        the interest rate on HBD in savings, expressed in basis points (previously for each HBD),
        is one of the values determined by the witnesses
    total_vesting_fund_hive:
      type: number
      x-sql-datatype: numeric
      description: >-
        the balance of the "counterweight" for these VESTS (total_vesting_shares) in the form of HIVE 
        (the price of VESTS is derived from these two values). A portion of the inflation is added to the balance,
        ensuring that each block corresponds to more HIVE for the VESTS
    total_vesting_shares:
      type: number
      x-sql-datatype: numeric
      description: the total amount of VEST present in the system
    total_reward_fund_hive:
      type: number
      x-sql-datatype: numeric
      description: deprecated after HF17
    virtual_supply:
      type: number
      x-sql-datatype: numeric
      description: >-
        the total amount of HIVE, including the HIVE that would be generated from converting HBD to HIVE at the current price
    current_supply:
      type: number
      x-sql-datatype: numeric
      description: the total amount of HIVE present in the system
    current_hbd_supply:
      type: number
      x-sql-datatype: numeric
      description: >-
        the total amount of HBD present in the system, including what is in the treasury
    dhf_interval_ledger:
      type: number
      x-sql-datatype: numeric
      description: >-
        the dhf_interval_ledger is a temporary HBD balance. Each block allocates a portion of inflation for proposal payouts,
        but these payouts occur every hour. To avoid cluttering the history with small amounts each block, 
        the new funds are first accumulated in the dhf_interval_ledger. Then, every HIVE_PROPOSAL_MAINTENANCE_PERIOD,
        the accumulated funds are transferred to the treasury account (this operation generates the virtual operation dhf_funding_operation),
        from where they are subsequently paid out to the approved proposals
    created_at:
      type: string
      format: date-time
      description: the timestamp when the block was created
    age:
      type: string
      x-sql-datatype: INTERVAL
      description: the time that has elapsed since the block was created. 
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_types.block CASCADE;
CREATE TYPE hafbe_types.block AS (
    "block_num" INT,
    "hash" bytea,
    "prev" bytea,
    "producer_account" TEXT,
    "transaction_merkle_root" bytea,
    "extensions" JSONB,
    "witness_signature" bytea,
    "signing_key" TEXT,
    "hbd_interest_rate" numeric,
    "total_vesting_fund_hive" numeric,
    "total_vesting_shares" numeric,
    "total_reward_fund_hive" numeric,
    "virtual_supply" numeric,
    "current_supply" numeric,
    "current_hbd_supply" numeric,
    "dhf_interval_ledger" numeric,
    "created_at" TIMESTAMP,
    "age" INTERVAL
);
-- openapi-generated-code-end

RESET ROLE;
