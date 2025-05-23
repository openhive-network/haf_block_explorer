SET ROLE hafbe_owner;

/** openapi:components:schemas
hafbe_types.witness:
  type: object
  properties:
    witness_name:
      type: string
      description: witness''s account name
    rank:
      type: integer
      description: >-
        the current rank of the witness according to the votes cast on
        the blockchain. The top 20 witnesses (ranks 1 - 20) will produce
        blocks each round.
    url:
      type: string
      description: the witness''s home page
    vests:
      type: string
      description: >-
        the total weight of votes cast in favor of this witness, expressed
        in VESTS
    votes_daily_change:
      type: string
      description: >-
        the increase or decrease in votes for this witness over the last 24
        hours, expressed in vests
    voters_num:
      type: integer
      description: the number of voters for this witness
    voters_num_daily_change:
      type: integer
      description: >-
        the increase or decrease in the number of voters voting for this
        witness over the last 24 hours
    price_feed:
      type: number
      description: the current price feed provided by the witness in HIVE/HBD
    bias:
      type: integer
      x-sql-datatype: NUMERIC
      description: >-
        When setting the price feed, you specify the base and quote. Typically, if market conditions are stable and,
        for example, HBD is trading at 0.25 USD on exchanges, a witness would set:
          base: 0.250 HBD
          quote: 1.000 HIVE
        (This indicates that one HIVE costs 0.25 HBD.)
        However, if the peg is not maintained and HBD does not equal 1 USD (either higher or lower),
        the witness can adjust the feed accordingly. For instance, if HBD is trading at only 0.90 USD on exchanges, the witness might set:
          base: 0.250 HBD
          quote: 1.100 HIVE
        In this case, the bias is 10%%
    feed_updated_at:
      type: string
      format: date-time
      description: timestamp when feed was updated
    block_size:
      type: integer
      description: the maximum block size the witness is currently voting for, in bytes
    signing_key:
      type: string
      description: the key used to verify blocks signed by this witness
    version:
      type: string
      description: the version of hived the witness is running
    missed_blocks:
      type: integer
      description: >-
        the number of blocks the witness should have generated but didn''t
        (over the entire lifetime of the blockchain)
    hbd_interest_rate:
      type: integer
      description: the interest rate the witness is voting for
    last_confirmed_block_num:
      type: integer
      description: the last block number created by the witness
    account_creation_fee:
      type: integer
      description: the cost of creating an account. 
*/
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_types.witness CASCADE;
CREATE TYPE hafbe_types.witness AS (
    "witness_name" TEXT,
    "rank" INT,
    "url" TEXT,
    "vests" TEXT,
    "votes_daily_change" TEXT,
    "voters_num" INT,
    "voters_num_daily_change" INT,
    "price_feed" FLOAT,
    "bias" NUMERIC,
    "feed_updated_at" TIMESTAMP,
    "block_size" INT,
    "signing_key" TEXT,
    "version" TEXT,
    "missed_blocks" INT,
    "hbd_interest_rate" INT,
    "last_confirmed_block_num" INT,
    "account_creation_fee" INT
);
-- openapi-generated-code-end

/** openapi:components:schemas
hafbe_types.witness_return:
  type: object
  properties:
    votes_updated_at:
      type: string
      format: date-time
      description: Time of cache update
    witness:
      $ref: '#/components/schemas/hafbe_types.witness'
      description: Witness parameters
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_types.witness_return CASCADE;
CREATE TYPE hafbe_types.witness_return AS (
    "votes_updated_at" TIMESTAMP,
    "witness" hafbe_types.witness
);
-- openapi-generated-code-end

/** openapi:components:schemas
hafbe_types.witnesses_return:
  type: object
  properties:
    total_witnesses:
      type: integer
      description: Total number of witnesses
    total_pages:
      type: integer
      description: Total number of pages
    votes_updated_at:
      type: string
      format: date-time
      description: Time of cache update
    witnesses:
      type: array
      items:
        $ref: '#/components/schemas/hafbe_types.witness'
      description: List of witness parameters
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_types.witnesses_return CASCADE;
CREATE TYPE hafbe_types.witnesses_return AS (
    "total_witnesses" INT,
    "total_pages" INT,
    "votes_updated_at" TIMESTAMP,
    "witnesses" hafbe_types.witness[]
);
-- openapi-generated-code-end

RESET ROLE;
