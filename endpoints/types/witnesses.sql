SET ROLE hafbe_owner;

-- Witness-related types for hafbe_backend

----------------------------------------------------------------------

/** openapi:components:schemas
hafbe_backend.witness_votes_change_window:
  type: object
  x-sql-datatype: JSON
  properties:
    total:
      type: string
      description: >-
        the change in the witness''s votes over the window, in VESTS: the sum
        of the cause fields below
    voters:
      type: integer
      description: the number of the witness''s voters whose events moved its votes
    rank_start:
      type: integer
      description: >-
        the witness''s rank at the window start, ranked like rank (votes, then
        voters, then id) on its votes minus this total and its voters then
    votes_cast:
      type: string
      description: votes cast, each at the voter''s weight when it voted, in VESTS
    votes_removed:
      type: string
      description: votes removed, each at the voter''s weight then, in VESTS
    power_down:
      type: string
      description: power-down withdrawals of the voters and their proxies, in VESTS
    power_up:
      type: string
      description: power-ups finishing their 30-day voting delay, in VESTS
    producer_reward:
      type: string
      description: block producer rewards paid in VESTS
    claimed_reward:
      type: string
      description: author and curation rewards claimed in VESTS
    proxy:
      type: string
      description: >-
        weight moved by proxies being set, changed or cleared, and votes
        removed by setting a proxy, in VESTS
    expired:
      type: string
      description: >-
        votes and proxies removed after a year without governance activity,
        in VESTS
    declined:
      type: string
      description: votes and proxies removed by declining voting rights, in VESTS
*/

/** openapi:components:schemas
hafbe_backend.witness_votes_change_breakdown:
  type: object
  x-sql-datatype: JSON
  properties:
    as_of_block:
      type: integer
      description: the last block processed when the breakdown was refreshed (every 100 blocks)
    today:
      $ref: '#/components/schemas/hafbe_backend.witness_votes_change_window'
      description: the change since 00:00 UTC
    7d:
      $ref: '#/components/schemas/hafbe_backend.witness_votes_change_window'
      description: the change over the 7 days up to as_of_block
*/

/** openapi:components:schemas
hafbe_backend.witness:
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
        the increase or decrease in votes for this witness since 00:00 UTC
        from votes cast and removed today, each valued at the voter''s
        current weight, expressed in vests
    voters_num:
      type: integer
      description: the number of voters for this witness
    voters_num_daily_change:
      type: integer
      description: >-
        the increase or decrease in the number of voters voting for this
        witness since 00:00 UTC
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
    votes_change_breakdown:
      $ref: '#/components/schemas/hafbe_backend.witness_votes_change_breakdown'
      x-sql-datatype: JSON
      description: >-
        the change in the witness''s votes broken down by cause, today and
        over 7 days; null until the first refresh
*/
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.witness CASCADE;
CREATE TYPE hafbe_backend.witness AS (
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
    "account_creation_fee" INT,
    "votes_change_breakdown" JSON
);
-- openapi-generated-code-end

/** openapi:components:schemas
hafbe_backend.witnesses_return:
  type: object
  properties:
    total_witnesses:
      type: integer
      description: Total number of witnesses
    total_pages:
      type: integer
      description: Total number of pages
    witnesses:
      type: array
      items:
        $ref: '#/components/schemas/hafbe_backend.witness'
      description: List of witness parameters
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.witnesses_return CASCADE;
CREATE TYPE hafbe_backend.witnesses_return AS (
    "total_witnesses" INT,
    "total_pages" INT,
    "witnesses" hafbe_backend.witness[]
);
-- openapi-generated-code-end

----------------------------------------------------------------------

/** openapi:components:schemas
hafbe_backend.witness_voter:
  type: object
  properties:
    voter_name:
      type: string
      description: account name of the voter
    vests:
      type: string
      description: number of vests this voter is directly voting with
    account_vests:
      type: string
      description: >-
        number of vests in the voter''s account.  if some vests are
        delegated, they will not be counted in voting
    proxied_vests:
      type: string
      description: the number of vests proxied to this account
    timestamp:
      type: string
      format: date-time
      description: the time this account last changed its voting power
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.witness_voter CASCADE;
CREATE TYPE hafbe_backend.witness_voter AS (
    "voter_name" TEXT,
    "vests" TEXT,
    "account_vests" TEXT,
    "proxied_vests" TEXT,
    "timestamp" TIMESTAMP
);
-- openapi-generated-code-end

/** openapi:components:schemas
hafbe_backend.witness_voter_history:
  type: object
  properties:
    total_votes:
      type: integer
      description: Total number of votes
    total_pages:
      type: integer
      description: Total number of pages
    voters:
      type: array
      items:
        $ref: '#/components/schemas/hafbe_backend.witness_voter'
      description: List of votes results
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.witness_voter_history CASCADE;
CREATE TYPE hafbe_backend.witness_voter_history AS (
    "total_votes" INT,
    "total_pages" INT,
    "voters" hafbe_backend.witness_voter[]
);
-- openapi-generated-code-end

----------------------------------------------------------------------

/** openapi:components:schemas
hafbe_backend.witness_votes_history_record:
  type: object
  properties:
    voter_name:
      type: string
      description: account name of the voter
    approve:
      type: boolean
      description: whether the voter approved or rejected the witness
    vests:
      type: string
      description: number of vests this voter is directly voting with
    account_vests:
      type: string
      description: >-
        number of vests in the voter''s account.  if some vests are
        delegated, they will not be counted in voting
    proxied_vests:
      type: string
      description: the number of vests proxied to this account
    timestamp:
      type: string
      format: date-time
      description: the time of the vote change
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.witness_votes_history_record CASCADE;
CREATE TYPE hafbe_backend.witness_votes_history_record AS (
    "voter_name" TEXT,
    "approve" BOOLEAN,
    "vests" TEXT,
    "account_vests" TEXT,
    "proxied_vests" TEXT,
    "timestamp" TIMESTAMP
);
-- openapi-generated-code-end

/** openapi:components:schemas
hafbe_backend.witness_votes_history:
  type: object
  properties:
    total_votes:
      type: integer
      description: Total number of votes
    total_pages:
      type: integer
      description: Total number of pages
    votes_history:
      type: array
      items:
        $ref: '#/components/schemas/hafbe_backend.witness_votes_history_record'
      description: List of witness votes
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.witness_votes_history CASCADE;
CREATE TYPE hafbe_backend.witness_votes_history AS (
    "total_votes" INT,
    "total_pages" INT,
    "votes_history" hafbe_backend.witness_votes_history_record[]
);
-- openapi-generated-code-end

RESET ROLE;
