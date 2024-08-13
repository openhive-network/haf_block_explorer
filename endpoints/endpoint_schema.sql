SET ROLE hafbe_owner;

/** openapi
openapi: 3.1.0
info:
  title: HAF Block Explorer
  description: >-
    HAF block explorer is an API for querying information about
    transactions/operations included in Hive blocks, as well as block producer
    (i.e. witness) information.
  license:
    name: MIT License
    url: https://opensource.org/license/mit
  version: 1.27.5
externalDocs:
  description: HAF Block Explorer gitlab repository
  url: https://gitlab.syncad.com/hive/haf_block_explorer
tags:
  - name: Block-numbers
    description: Informations about block numbers
  - name: Accounts
    description: Informations about accounts
  - name: Witnesses
    description: Informations about witnesses
  - name: Other
    description: General API informations
servers:
  - url: /hafbe
 */

CREATE SCHEMA IF NOT EXISTS hafbe_endpoints AUTHORIZATION hafbe_owner;

DO $__$
DECLARE 
  swagger_url TEXT;
BEGIN
  swagger_url := current_setting('custom.swagger_url')::TEXT;
  
EXECUTE FORMAT(
'create or replace function hafbe_endpoints.root() returns json as $_$
declare
-- openapi-spec
-- openapi-generated-code-begin
  openapi json = $$
{
  "components": {
    "schemas": {
      "hafbe_types.sort_direction": {
        "type": "string",
        "enum": [
          "asc",
          "desc"
        ]
      },
      "hafbe_types.order_by_votes": {
        "type": "string",
        "enum": [
          "voter",
          "vests",
          "account_vests",
          "proxied_vests",
          "timestamp"
        ]
      },
      "hafbe_types.order_by_witness": {
        "type": "string",
        "enum": [
          "witness",
          "rank",
          "url",
          "votes",
          "votes_daily_change",
          "voters_num",
          "voters_num_daily_change",
          "price_feed",
          "bias",
          "block_size",
          "signing_key",
          "version"
        ]
      },
      "hafbe_types.witness": {
        "type": "object",
        "properties": {
          "witness": {
            "type": "string",
            "description": "the name of the witness account"
          },
          "rank": {
            "type": "integer",
            "description": "the current rank of the witness according to the votes cast on the    blockchain.  The top 20 witnesses (ranks 1 - 20) will produce blocks each round."
          },
          "url": {
            "type": "string",
            "description": "the witness''s home page"
          },
          "vests": {
            "type": "string",
            "description": "the total weight of votes cast in favor of this witness, expressed in VESTS"
          },
          "vests_hive_power": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
            "description": "the total weight of votes cast in favor of this witness, expressed in HIVE power, at the current ratio"
          },
          "votes_daily_change": {
            "type": "string",
            "description": "the increase or decrease in votes for this witness over the last 24 hours, expressed in vests"
          },
          "votes_daily_change_hive_power": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
            "description": "the increase or decrease in votes for this witness over the last 24 hours, expressed in HIVE power, at the current ratio"
          },
          "voters_num": {
            "type": "integer",
            "description": "the number of voters supporting this witness"
          },
          "voters_num_daily_change": {
            "type": "integer",
            "description": "the increase or decrease in the number of voters voting for this witness over the last 24 hours"
          },
          "price_feed": {
            "type": "number",
            "description": "the current price feed provided by the witness in HIVE/HBD"
          },
          "bias": {
            "type": "integer",
            "x-sql-datatype": "NUMERIC",
            "description": "When setting the price feed, you specify the base and quote. Typically, if market conditions are stable and, for example, HBD is trading at 0.25 USD on exchanges, a witness would set:\n  base: 0.250 HBD\n  quote: 1.000 HIVE\n(This indicates that one HIVE costs 0.25 HBD.) However, if the peg is not maintained and HBD does not equal 1 USD (either higher or lower), the witness can adjust the feed accordingly. For instance, if HBD is trading at only 0.90 USD on exchanges, the witness might set:\n  base: 0.250 HBD\n  quote: 1.100 HIVE\nIn this case, the bias is 10%%"
          },
          "feed_updated_at": {
            "type": "string",
            "format": "date-time",
            "description": "the timestamp when feed was updated"
          },
          "block_size": {
            "type": "integer",
            "description": "the maximum block size the witness is currently voting for, in bytes"
          },
          "signing_key": {
            "type": "string",
            "description": "the key used to verify blocks signed by this witness"
          },
          "version": {
            "type": "string",
            "description": "the version of hived the witness is running"
          },
          "missed_blocks": {
            "type": "integer",
            "description": "the number of blocks the witness should have generated but didn''t (over the entire lifetime of the blockchain)"
          },
          "hbd_interest_rate": {
            "type": "integer",
            "description": "the interest rate the witness is voting for"
          }
        }
      },
      "hafbe_types.array_of_witnesses": {
        "type": "array",
        "items": {
          "$ref": "#/components/schemas/hafbe_types.witness"
        }
      },
      "hafbe_types.witness_voter": {
        "type": "object",
        "properties": {
          "voter": {
            "type": "string",
            "description": "account name of the voter"
          },
          "vests": {
            "type": "string",
            "description": "number of vests this voter is directly voting with"
          },
          "votes_hive_power": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
            "description": "number of vests this voter is directly voting with, expressed in HIVE power, at the current ratio"
          },
          "account_vests": {
            "type": "string",
            "description": "number of vests in the voter''s account.  if some vests are delegated, they will not be counted in voting"
          },
          "account_hive_power": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
            "description": "number of vests in the voter''s account, expressed in HIVE power, at the current ratio.  if some vests are delegated, they will not be counted in voting"
          },
          "proxied_vests": {
            "type": "string",
            "description": "the number of vests proxied to this account"
          },
          "proxied_hive_power": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
            "description": "the number of vests proxied to this account expressed in HIVE power, at the current ratio"
          },
          "timestamp": {
            "type": "string",
            "format": "date-time",
            "description": "the time this account last changed its voting power"
          }
        }
      },
      "hafbe_types.array_of_witness_voters": {
        "type": "array",
        "items": {
          "$ref": "#/components/schemas/hafbe_types.witness_voter"
        }
      },
      "hafbe_types.witness_votes_history_record": {
        "type": "object",
        "properties": {
          "voter": {
            "type": "string",
            "description": "account name of the voter"
          },
          "approve": {
            "type": "boolean",
            "description": "whether the voter approved or rejected the witness"
          },
          "vests": {
            "type": "string",
            "description": "number of vests this voter is directly voting with"
          },
          "votes_hive_power": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
            "description": "number of vests this voter is directly voting with, expressed in HIVE power, at the current ratio"
          },
          "account_vests": {
            "type": "string",
            "description": "number of vests in the voter''s account.  if some vests are delegated, they will not be counted in voting"
          },
          "account_hive_power": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
            "description": "number of vests in the voter''s account, expressed in HIVE power, at the current ratio.  if some vests are delegated, they will not be counted in voting"
          },
          "proxied_vests": {
            "type": "string",
            "description": "the number of vests proxied to this account"
          },
          "proxied_hive_power": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
            "description": "the number of vests proxied to this account expressed in HIVE power, at the current ratio"
          },
          "timestamp": {
            "type": "string",
            "format": "date-time",
            "description": "the time of the vote change"
          }
        }
      },
      "hafbe_types.array_of_witness_vote_history_records": {
        "type": "array",
        "items": {
          "$ref": "#/components/schemas/hafbe_types.witness_votes_history_record"
        }
      },
      "hafbe_types.account": {
        "type": "object",
        "properties": {
          "id": {
            "type": "integer",
            "description": "account''s identification number"
          },
          "name": {
            "type": "string",
            "description": "account''s name"
          },
          "can_vote": {
            "type": "boolean",
            "description": "information whether the account can vote or not"
          },
          "mined": {
            "type": "boolean",
            "description": "information whether made a prove of work"
          },
          "proxy": {
            "type": "string",
            "description": "the username to which the account has designated as its proxy"
          },
          "recovery_account": {
            "type": "string",
            "description": "the username to which the account has designated as its recovery account"
          },
          "last_account_recovery": {
            "type": "string",
            "format": "date-time",
            "description": "time when the last account recovery was performed"
          },
          "created": {
            "type": "string",
            "format": "date-time",
            "description": "date of account creation"
          },
          "reputation": {
            "type": "integer",
            "description": "numerical rating of the user  based on upvotes and downvotes on user''s posts"
          },
          "json_metadata": {
            "type": "string",
            "description": "parameter encompasses personalized profile information"
          },
          "posting_json_metadata": {
            "type": "string",
            "description": "parameter encompasses personalized profile information"
          },
          "profile_image": {
            "type": "string",
            "description": "url to profile image"
          },
          "hbd_balance": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
            "description": "number of HIVE backed dollars the account has"
          },
          "balance": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
            "description": "account''s HIVE balance"
          },
          "vesting_shares": {
            "type": "string",
            "description": "account''s VEST balance"
          },
          "vesting_balance": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
            "description": "the VEST balance, presented in HIVE,  is calculated based on the current HIVE price"
          },
          "hbd_saving_balance": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
            "description": "saving balance of HIVE backed dollars"
          },
          "savings_balance": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
            "description": "HIVE saving balance"
          },
          "savings_withdraw_requests": {
            "type": "integer",
            "description": "number representing how many payouts are pending  from user''s saving balance "
          },
          "reward_hbd_balance": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
            "description": "not yet claimed HIVE backed dollars  stored in hbd reward balance"
          },
          "reward_hive_balance": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
            "description": "not yet claimed HIVE  stored in hive reward balance"
          },
          "reward_vesting_balance": {
            "type": "string",
            "description": "not yet claimed VESTS  stored in vest reward balance"
          },
          "reward_vesting_hive": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
            "description": "the reward vesting balance, denominated in HIVE,  is determined by the prevailing HIVE price at the time of reward reception"
          },
          "posting_rewards": {
            "type": "string",
            "description": "rewards obtained by posting and commenting expressed in VEST"
          },
          "curation_rewards": {
            "type": "string",
            "description": "curator''s reward expressed in VEST"
          },
          "delegated_vesting_shares": {
            "type": "string",
            "description": "VESTS delegated to another user,  account''s power is lowered by delegated VESTS"
          },
          "received_vesting_shares": {
            "type": "string",
            "description": "VESTS received from another user,  account''s power is increased by received VESTS"
          },
          "proxied_vsf_votes": {
            "type": "string",
            "x-sql-datatype": "JSON",
            "description": "recursive proxy of VESTS "
          },
          "withdrawn": {
            "type": "string",
            "description": "the total VESTS already withdrawn from active withdrawals"
          },
          "vesting_withdraw_rate": {
            "type": "string",
            "description": "received until the withdrawal is complete,  with each installment amounting to 1/13 of the withdrawn total"
          },
          "to_withdraw": {
            "type": "string",
            "description": "the remaining total VESTS needed to complete withdrawals"
          },
          "withdraw_routes": {
            "type": "integer",
            "description": "list of account receiving the part of a withdrawal"
          },
          "delayed_vests": {
            "type": "string",
            "description": "blocked VESTS by a withdrawal"
          },
          "witness_votes": {
            "type": "string",
            "x-sql-datatype": "JSON",
            "description": "the roster of witnesses voted by the account"
          },
          "witnesses_voted_for": {
            "type": "integer",
            "description": "count of witness_votes"
          },
          "ops_count": {
            "type": "integer",
            "description": "the number of operations performed by the account"
          },
          "is_witness": {
            "type": "boolean",
            "description": "whether account is a witness"
          }
        }
      },
      "hafbe_types.account_authority": {
        "type": "object",
        "properties": {
          "owner": {
            "type": "string",
            "x-sql-datatype": "JSON",
            "description": "the most powerful key because it can change any key of an account, including the owner key. Ideally it is meant to be stored offline, and only used to recover a compromised account"
          },
          "active": {
            "type": "string",
            "x-sql-datatype": "JSON",
            "description": "key meant for more sensitive tasks such as transferring funds, power up/down transactions, converting Hive Dollars, voting for witnesses, updating profile details and avatar, and placing a market order"
          },
          "posting": {
            "type": "string",
            "x-sql-datatype": "JSON",
            "description": "key allows accounts to post, comment, edit, vote, reblog and follow or mute other accounts"
          },
          "memo": {
            "type": "string",
            "description": "currently the memo key is not used"
          },
          "witness_signing": {
            "type": "string",
            "description": "key used to sign block by witness"
          }
        }
      },
      "hafbe_types.comment_history": {
        "type": "object",
        "properties": {
          "permlink": {
            "type": "string",
            "description": "unique post identifier containing post''s title and generated number"
          },
          "block_num": {
            "type": "integer",
            "description": "operation block number"
          },
          "operation_id": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
            "description": "unique operation identifier with an encoded block number and operation type id"
          },
          "created_at": {
            "type": "string",
            "format": "date-time",
            "description": "creation date"
          },
          "trx_hash": {
            "type": "string",
            "description": "hash of the transaction"
          },
          "operation": {
            "type": "string",
            "x-sql-datatype": "JSONB",
            "description": "operation body"
          }
        }
      },
      "hafbe_types.latest_blocks": {
        "type": "object",
        "properties": {
          "block_num": {
            "type": "integer",
            "description": "block number"
          },
          "witness": {
            "type": "string",
            "description": "witness that created the block"
          },
          "ops_count": {
            "type": "string",
            "x-sql-datatype": "JSON",
            "description": "count of each operation type"
          }
        }
      },
      "hafbe_types.array_of_latest_blocks": {
        "type": "array",
        "items": {
          "$ref": "#/components/schemas/hafbe_types.latest_blocks"
        }
      },
      "hafbe_types.block": {
        "type": "object",
        "properties": {
          "block_num": {
            "type": "integer",
            "description": "block number"
          },
          "hash": {
            "type": "string",
            "description": "block hash in a blockchain is a unique, fixed-length string generated  by applying a cryptographic hash function to a block''s contents"
          },
          "prev": {
            "type": "string",
            "description": "hash of a previous block"
          },
          "producer_account": {
            "type": "string",
            "description": "account name of block''s producer"
          },
          "transaction_merkle_root": {
            "type": "string",
            "description": "single hash representing the combined hashes of all transactions in a block"
          },
          "extensions": {
            "type": "string",
            "x-sql-datatype": "JSONB",
            "description": "various additional data/parameters related to the subject at hand. Most often, there''s nothing specific, but it''s a mechanism for extending various functionalities where something might appear in the future."
          },
          "witness_signature": {
            "type": "string",
            "description": "witness signature"
          },
          "signing_key": {
            "type": "string",
            "description": "it refers to the public key of the witness used for signing blocks and other witness operations"
          },
          "hbd_interest_rate": {
            "type": "number",
            "x-sql-datatype": "numeric",
            "description": "the interest rate on HBD in savings, expressed in basis points (previously for each HBD), is one of the values determined by the witnesses"
          },
          "total_vesting_fund_hive": {
            "type": "number",
            "x-sql-datatype": "numeric",
            "description": "the balance of the \"counterweight\" for these VESTS (total_vesting_shares) in the form of HIVE  (the price of VESTS is derived from these two values). A portion of the inflation is added to the balance, ensuring that each block corresponds to more HIVE for the VESTS"
          },
          "total_vesting_shares": {
            "type": "number",
            "x-sql-datatype": "numeric",
            "description": "the total amount of VEST present in the system"
          },
          "total_reward_fund_hive": {
            "type": "number",
            "x-sql-datatype": "numeric",
            "description": "deprecated after HF17"
          },
          "virtual_supply": {
            "type": "number",
            "x-sql-datatype": "numeric",
            "description": "the total amount of HIVE, including the HIVE that would be generated from converting HBD to HIVE at the current price"
          },
          "current_supply": {
            "type": "number",
            "x-sql-datatype": "numeric",
            "description": "the total amount of HIVE present in the system"
          },
          "current_hbd_supply": {
            "type": "number",
            "x-sql-datatype": "numeric",
            "description": "the total amount of HBD present in the system, including what is in the treasury"
          },
          "dhf_interval_ledger": {
            "type": "number",
            "x-sql-datatype": "numeric",
            "description": "the dhf_interval_ledger is a temporary HBD balance. Each block allocates a portion of inflation for proposal payouts, but these payouts occur every hour. To avoid cluttering the history with small amounts each block,  the new funds are first accumulated in the dhf_interval_ledger. Then, every HIVE_PROPOSAL_MAINTENANCE_PERIOD, the accumulated funds are transferred to the treasury account (this operation generates the virtual operation dhf_funding_operation), from where they are subsequently paid out to the approved proposals"
          },
          "created_at": {
            "type": "string",
            "format": "date-time",
            "description": "the timestamp when the block was created"
          }
        }
      },
      "hafbe_types.block_by_ops": {
        "type": "object",
        "properties": {
          "block_num": {
            "type": "integer",
            "description": "block number"
          },
          "op_type_id": {
            "type": "array",
            "items": {
              "type": "integer"
            },
            "x-sql-datatype": "INT[]",
            "description": "list of operation types"
          }
        }
      },
      "hafbe_types.array_of_block_by_ops": {
        "type": "array",
        "items": {
          "$ref": "#/components/schemas/hafbe_types.block_by_ops"
        }
      },
      "hafbe_types.operation": {
        "type": "object",
        "properties": {
          "op": {
            "type": "string",
            "x-sql-datatype": "JSONB",
            "description": "operation body"
          },
          "block": {
            "type": "integer",
            "description": "operation block number"
          },
          "trx_id": {
            "type": "string",
            "description": "hash of the transaction"
          },
          "op_pos": {
            "type": "integer",
            "description": "operation identifier that indicates its sequence number in transaction"
          },
          "op_type_id": {
            "type": "integer",
            "description": "operation type identifier"
          },
          "timestamp": {
            "type": "string",
            "format": "date-time",
            "description": "creation date"
          },
          "virtual_op": {
            "type": "boolean",
            "description": "true if is a virtual operation"
          },
          "operation_id": {
            "type": "string",
            "description": "unique operation identifier with an encoded block number and operation type id"
          },
          "trx_in_block": {
            "type": "integer",
            "x-sql-datatype": "SMALLINT",
            "description": "transaction identifier that indicates its sequence number in block"
          }
        }
      },
      "hafbe_types.op_types_count": {
        "type": "object",
        "properties": {
          "op_type_id": {
            "type": "integer",
            "description": "operation type id"
          },
          "count": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
            "description": "number of the operations in block"
          }
        }
      },
      "hafbe_types.array_of_op_types_count": {
        "type": "array",
        "items": {
          "$ref": "#/components/schemas/hafbe_types.op_types_count"
        }
      }
    }
  },
  "openapi": "3.1.0",
  "info": {
    "title": "HAF Block Explorer",
    "description": "HAF block explorer is an API for querying information about transactions/operations included in Hive blocks, as well as block producer (i.e. witness) information.",
    "license": {
      "name": "MIT License",
      "url": "https://opensource.org/license/mit"
    },
    "version": "1.27.5"
  },
  "externalDocs": {
    "description": "HAF Block Explorer gitlab repository",
    "url": "https://gitlab.syncad.com/hive/haf_block_explorer"
  },
  "tags": [
    {
      "name": "Block-numbers",
      "description": "Informations about block numbers"
    },
    {
      "name": "Accounts",
      "description": "Informations about accounts"
    },
    {
      "name": "Witnesses",
      "description": "Informations about witnesses"
    },
    {
      "name": "Other",
      "description": "General API informations"
    }
  ],
  "servers": [
    {
      "url": "/hafbe"
    }
  ],
  "paths": {
    "/witnesses": {
      "get": {
        "tags": [
          "Witnesses"
        ],
        "summary": "List witnesses",
        "description": "List all witnesses (both active and standby)\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_witnesses(2);`\n\nREST call example\n* `GET ''https://%1$s/hafbe/witnesses?result-limit=2''`\n",
        "operationId": "hafbe_endpoints.get_witnesses",
        "parameters": [
          {
            "in": "query",
            "name": "result-limit",
            "required": false,
            "schema": {
              "type": "integer",
              "default": 100
            },
            "description": "For pagination, return at most `result-limit` witnesses"
          },
          {
            "in": "query",
            "name": "offset",
            "required": false,
            "schema": {
              "type": "integer",
              "default": 0
            },
            "description": "For pagination, start at the `offset` witness"
          },
          {
            "in": "query",
            "name": "sort",
            "required": false,
            "schema": {
              "$ref": "#/components/schemas/hafbe_types.order_by_witness",
              "default": "votes"
            },
            "description": "Sort key:\n\n * `witness` - the witness name\n\n * `rank` - their current rank (highest weight of votes => lowest rank)\n\n * `url` - the witness url\n\n * `votes` - total number of votes\n\n * `votes_daily_change` - change in `votes` in the last 24 hours\n\n * `voters_num` - total number of voters approving the witness\n\n * `voters_num_daily_change` - change in `voters_num` in the last 24 hours\n\n * `price_feed` - their current published value for the HIVE/HBD price feed\n\n * `bias` - if HBD is trading at only 0.90 USD on exchanges, the witness might set:\n        base: 0.250 HBD\n        quote: 1.100 HIVE\n      In this case, the bias is 10%%\n\n * `block_size` - the block size they''re voting for\n\n * `signing_key` - the witness'' block-signing public key\n\n * `version` - the version of hived the witness is running\n"
          },
          {
            "in": "query",
            "name": "direction",
            "required": false,
            "schema": {
              "$ref": "#/components/schemas/hafbe_types.sort_direction",
              "default": "desc"
            },
            "description": "Sort order:\n\n * `asc` - Ascending, from A to Z or smallest to largest\n\n * `desc` - Descending, from Z to A or largest to smallest\n"
          }
        ],
        "responses": {
          "200": {
            "description": "The list of witnesses\n\n* Returns array of `hafbe_types.witness`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hafbe_types.array_of_witnesses"
                },
                "example": [
                  {
                    "witnes\"": "roadscape",
                    "rank": 1,
                    "url": "https://steemit.com/witness-category/@roadscape/witness-roadscape",
                    "vests": "94172201023355097",
                    "vests_hive_power": 31350553033,
                    "votes_daily_change": "0",
                    "votes_daily_change_hive_power": "0,",
                    "voters_num": 306,
                    "voters_num_daily_change": 0,
                    "price_feed": 0.539,
                    "bias": 0,
                    "feed_updated_at": "2016-09-15T16:07:42",
                    "block_size": 65536,
                    "signing_key": "STM5AS7ZS33pzTf1xbTi8ZUaUeVAZBsD7QXGrA51HvKmvUDwVbFP9",
                    "version": "0.13.0",
                    "missed_blocks": 129,
                    "hbd_interest_rate": 1000
                  },
                  {
                    "witness": "arhag",
                    "rank": 2,
                    "url": "https://steemit.com/witness-category/@arhag/witness-arhag",
                    "vests": "91835048921097725",
                    "vests_hive_power": 30572499530,
                    "votes_daily_change": "0",
                    "votes_daily_change_hive_power": 0,
                    "voters_num": 348,
                    "voters_num_daily_change": 0,
                    "price_feed": 0.536,
                    "bias": 0,
                    "feed_updated_at": "2016-09-15T19:31:18",
                    "block_size": 65536,
                    "signing_key": "STM8kvk4JH2m6ZyHBGNor4qk2Zwdi2MJAjMYUpfqiicCKu7HqAeZh",
                    "version": "0.13.0",
                    "missed_blocks": 61,
                    "hbd_interest_rate": 1000
                  }
                ]
              }
            }
          }
        }
      }
    },
    "/witnesses/{account-name}": {
      "get": {
        "tags": [
          "Witnesses"
        ],
        "summary": "Get a single witness",
        "description": "Return a single witness given their account name\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_witness(''blocktrades'');`\n\nREST call example\n* `GET ''https://%1$s/hafbe/witnesses/blocktrades''`\n",
        "operationId": "hafbe_endpoints.get_witness",
        "parameters": [
          {
            "in": "path",
            "name": "account-name",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "The witness account name"
          }
        ],
        "responses": {
          "200": {
            "description": "The witness stats\n\n* Returns `hafbe_types.witness`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hafbe_types.witness"
                },
                "example": {
                  "witness": "blocktrades",
                  "rank": 8,
                  "url": "https://blocktrades.us",
                  "vests": "82373419958692803",
                  "vests_hive_power": 27422660221,
                  "votes_daily_change": "0",
                  "votes_daily_change_hive_power": 0,
                  "voters_num": 263,
                  "voters_num_daily_change": 0,
                  "price_feed": 0.545,
                  "bias": 0,
                  "feed_updated_at": "2016-09-15T16:02:21",
                  "block_size": 65536,
                  "signing_key": "STM4vmVc3rErkueyWNddyGfmjmLs3Rr4i7YJi8Z7gFeWhakXM4nEz",
                  "version": "0.13.0",
                  "missed_blocks": 935,
                  "hbd_interest_rate": 1000
                }
              }
            }
          },
          "404": {
            "description": "No such witness"
          }
        }
      }
    },
    "/witnesses/{account-name}/voters": {
      "get": {
        "tags": [
          "Witnesses"
        ],
        "summary": "Get information about the voters for a witness",
        "description": "Get information about the voters voting for a given witness\n\nSQL example      \n* `SELECT * FROM hafbe_endpoints.get_witness_voters(''blocktrades'');`\n\nREST call example\n* `GET ''https://%1$s/hafbe/witnesses/blocktrades/voters?result-limit=2''`\n",
        "operationId": "hafbe_endpoints.get_witness_voters",
        "parameters": [
          {
            "in": "path",
            "name": "account-name",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "The witness account name"
          },
          {
            "in": "query",
            "name": "sort",
            "required": false,
            "schema": {
              "$ref": "#/components/schemas/hafbe_types.order_by_votes",
              "default": "vests"
            },
            "description": "Sort order:\n\n * `voter` - account name of voter\n\n * `vests` - total voting power = account_vests + proxied_vests of voter\n\n * `account_vests` - direct vests of voter\n\n * `proxied_vests` - proxied vests of voter\n\n * `timestamp` - last time voter voted for the witness\n"
          },
          {
            "in": "query",
            "name": "direction",
            "required": false,
            "schema": {
              "$ref": "#/components/schemas/hafbe_types.sort_direction",
              "default": "desc"
            },
            "description": "Sort order:\n\n * `asc` - Ascending, from A to Z or smallest to largest\n\n * `desc` - Descending, from Z to A or largest to smallest\n"
          },
          {
            "in": "query",
            "name": "result-limit",
            "required": false,
            "schema": {
              "type": "integer",
              "default": 2147483647
            },
            "description": "Return at most `result-limit` voters"
          }
        ],
        "responses": {
          "200": {
            "description": "The number of voters currently voting for this witness\n\n* Returns array of `hafbe_types.witness_voter`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hafbe_types.array_of_witness_voters"
                },
                "example": [
                  {
                    "voter": "blocktrades",
                    "vests": "13155953611548185",
                    "votes_hive_power": 4379704593,
                    "account_vests": "8172549681941451",
                    "account_hive_power": 2720696229,
                    "proxied_vests": "4983403929606734",
                    "proxied_hive_power": 1659008364,
                    "timestamp": "2016-04-15T02:19:57"
                  },
                  {
                    "voter": "dan",
                    "vests": "9928811304950768",
                    "votes_hive_power": 3305367423,
                    "account_vests": "9928811304950768",
                    "account_hive_power": 3305367423,
                    "proxied_vests": "0",
                    "proxied_hive_power": 0,
                    "timestamp": "2016-06-27T12:41:42"
                  }
                ]
              }
            }
          },
          "404": {
            "description": "No such witness"
          }
        }
      }
    },
    "/witnesses/{account-name}/voters/count": {
      "get": {
        "tags": [
          "Witnesses"
        ],
        "summary": "Get the number of voters for a witness",
        "description": "Get the number of voters for a witness given their account name\n\nSQL example      \n* `SELECT * FROM hafbe_endpoints.get_witness_voters_num(''blocktrades'');`\n\nREST call example\n* `GET ''https://%1$s/hafbe/witnesses/blocktrades/voters/count''`\n",
        "operationId": "hafbe_endpoints.get_witness_voters_num",
        "parameters": [
          {
            "in": "path",
            "name": "account-name",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "The witness account name"
          }
        ],
        "responses": {
          "200": {
            "description": "The number of voters currently voting for this witness\n\n* Returns `INT`\n",
            "content": {
              "application/json": {
                "schema": {
                  "type": "integer"
                },
                "example": 263
              }
            }
          },
          "404": {
            "description": "No such witness"
          }
        }
      }
    },
    "/witnesses/{account-name}/votes/history": {
      "get": {
        "tags": [
          "Witnesses"
        ],
        "summary": "Get the history of votes for this witness",
        "description": "Get information about each vote cast for this witness\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_witness_votes_history(''blocktrades'');`\n\nREST call example\n* `GET ''https://%1$s/hafbe/witnesses/blocktrades/votes/history?result-limit=2''`\n",
        "operationId": "hafbe_endpoints.get_witness_votes_history",
        "parameters": [
          {
            "in": "path",
            "name": "account-name",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "The witness account name"
          },
          {
            "in": "query",
            "name": "sort",
            "required": false,
            "schema": {
              "$ref": "#/components/schemas/hafbe_types.order_by_votes",
              "default": "timestamp"
            },
            "description": "Sort order:\n\n * `voter` - account name of voter\n\n * `vests` - total voting power = account_vests + proxied_vests of voter\n\n * `account_vests` - direct vests of voter\n\n * `proxied_vests` - proxied vests of voter\n\n * `timestamp` - time when user performed vote/unvote operation\n"
          },
          {
            "in": "query",
            "name": "direction",
            "required": false,
            "schema": {
              "$ref": "#/components/schemas/hafbe_types.sort_direction",
              "default": "desc"
            }
          },
          {
            "in": "query",
            "name": "result-limit",
            "required": false,
            "schema": {
              "type": "integer",
              "default": 100
            },
            "description": "Sort order:\n\n * `asc` - Ascending, from A to Z or smallest to largest\n\n * `desc` - Descending, from Z to A or largest to smallest\n"
          },
          {
            "in": "query",
            "name": "start-date",
            "required": false,
            "schema": {
              "type": "string",
              "format": "date-time",
              "default": null
            },
            "description": "Return only votes newer than `start-date`"
          },
          {
            "in": "query",
            "name": "end-date",
            "required": false,
            "schema": {
              "type": "string",
              "format": "date-time",
              "x-sql-default-value": "now()"
            },
            "description": "Return only votes older than `end-date`"
          }
        ],
        "responses": {
          "200": {
            "description": "The number of voters currently voting for this witness\n\n* Returns array of `hafbe_types.witness_vote_history_record`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hafbe_types.array_of_witness_vote_history_records"
                },
                "example": [
                  {
                    "voter": "jeremyfromwi",
                    "approve": true,
                    "vests": "441156952466",
                    "votes_hive_power": 146864,
                    "account_vests": "441156952466",
                    "account_hive_power": 146864,
                    "proxied_vests": "0",
                    "proxied_hive_power": 0,
                    "timestamp": "2016-09-15T07:07:15"
                  },
                  {
                    "voter": "cryptomental",
                    "approve": true,
                    "vests": "686005633844",
                    "votes_hive_power": 228376,
                    "account_vests": "686005633844",
                    "account_hive_power": 228376,
                    "proxied_vests": "0",
                    "proxied_hive_power": 0,
                    "timestamp": "2016-09-15T07:00:51"
                  }
                ]
              }
            }
          },
          "404": {
            "description": "No such witness"
          }
        }
      }
    },
    "/accounts/{account-name}": {
      "get": {
        "tags": [
          "Accounts"
        ],
        "summary": "Get account info",
        "description": "Get information about account''s balances and parameters\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_account(''blocktrades'');`\n\nREST call example\n* `GET ''https://%1$s/hafbe/accounts/blocktrades''`\n",
        "operationId": "hafbe_endpoints.get_account",
        "parameters": [
          {
            "in": "path",
            "name": "account-name",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "Name of the account"
          }
        ],
        "responses": {
          "200": {
            "description": "The account''s parameters\n\n* Returns `hafbe_types.account`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hafbe_types.account"
                },
                "example": [
                  {
                    "id": 440,
                    "name": "blocktrades",
                    "can_vote": true,
                    "mined": true,
                    "proxy": "",
                    "recovery_account": "steem",
                    "last_account_recovery": "1970-01-01T00:00:00",
                    "created": "2016-03-30T00:04:36",
                    "reputation": "69,",
                    "json_metadata": "",
                    "posting_json_metadata": "",
                    "profile_image": "",
                    "hbd_balance": 77246982,
                    "balance": 29594875,
                    "vesting_shares": "8172549681941451",
                    "vesting_balance": 2720696229,
                    "hbd_saving_balance": 0,
                    "savings_balance": 0,
                    "savings_withdraw_requests": 0,
                    "reward_hbd_balance": 0,
                    "reward_hive_balance": 0,
                    "reward_vesting_balance": "0",
                    "reward_vesting_hive": 0,
                    "posting_rewards": "65916519",
                    "curation_rewards": "196115157",
                    "delegated_vesting_shares": "0",
                    "received_vesting_shares": "0",
                    "proxied_vsf_votes": "[4983403929606734, 0, 0, 0]",
                    "withdrawn": "804048182205290",
                    "vesting_withdraw_rate": "80404818220529",
                    "to_withdraw": "8362101094935031",
                    "withdraw_routes": 4,
                    "delayed_vests": "0",
                    "witness_votes": [
                      "steempty",
                      "blocktrades",
                      "datasecuritynode",
                      "steemed",
                      "silversteem",
                      "witness.svk",
                      "joseph",
                      "smooth.witness",
                      "gtg"
                    ],
                    "witnesses_voted_for": 9,
                    "ops_count": 219867,
                    "is_witness": true
                  }
                ]
              }
            }
          },
          "404": {
            "description": "No such account in the database"
          }
        }
      }
    },
    "/accounts/{account-name}/authority": {
      "get": {
        "tags": [
          "Accounts"
        ],
        "summary": "Get account info",
        "description": "Get information about account''s OWNER, ACTIVE, POSTING, memo and signing authorities\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_account_authority(''blocktrades'');`\n\nREST call example\n* `GET ''https://%1$s/hafbe/accounts/blocktrades/authority''` \n",
        "operationId": "hafbe_endpoints.get_account_authority",
        "parameters": [
          {
            "in": "path",
            "name": "account-name",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "Name of the account"
          }
        ],
        "responses": {
          "200": {
            "description": "List of account''s authorities\n\n* Returns `hafbe_types.account_authority`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hafbe_types.account_authority"
                },
                "example": [
                  {
                    "owner": {
                      "key_auth": [
                        [
                          "STM7WdrxF6iuSiHUB4maoLGXXBKXbqAJ9AZbzACX1MPK2AkuCh23S",
                          "1"
                        ]
                      ],
                      "account_auth": [],
                      "weight_threshold": 1
                    },
                    "active": {
                      "key_auth": [
                        [
                          "STM5vgGoHBrUuDCspAPYi3dLwSyistyrz61NWkZNUAXAifZJaDLPF",
                          "1"
                        ]
                      ],
                      "account_auth": [],
                      "weight_threshold": 1
                    },
                    "posting": {
                      "key_auth": [
                        [
                          "STM5SaNVKJgy6ghnkNoMAprTxSDG55zps21Bo8qe1rnHmwAR4LzzC",
                          "1"
                        ]
                      ],
                      "account_auth": [],
                      "weight_threshold": 1
                    },
                    "memo": "STM7EAUbNf1CdTrMbydPoBTRMG4afXCoAErBJYevhgne6zEP6rVBT",
                    "witness_signing": "STM4vmVc3rErkueyWNddyGfmjmLs3Rr4i7YJi8Z7gFeWhakXM4nEz"
                  }
                ]
              }
            }
          },
          "404": {
            "description": "No such account in the database"
          }
        }
      }
    },
    "/accounts/{account-name}/comment-operations": {
      "get": {
        "tags": [
          "Accounts"
        ],
        "summary": "Get comment related operations",
        "description": "List operations related to account and optionally filtered by permlink,\ntime/blockrange and comment related operations\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_comment_operations(''blocktrades'');`\n\nREST call example\n* `GET ''https://%1$s/hafbe/accounts/blocktrades/comment-operations?page-size=2&from-block=4000000&to-block=5000000''`\n",
        "operationId": "hafbe_endpoints.get_comment_operations",
        "parameters": [
          {
            "in": "path",
            "name": "account-name",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "Filter operations by the account that created them"
          },
          {
            "in": "query",
            "name": "operation-types",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "List of operations: if the parameter is NULL, all operations will be included\ncomment related op type ids: `0, 1, 17, 19, 51, 52, 53, 61, 63, 72, 73`\n"
          },
          {
            "in": "query",
            "name": "page",
            "required": false,
            "schema": {
              "type": "integer",
              "default": 1
            },
            "description": "Return page on `page` number, defaults to `1`"
          },
          {
            "in": "query",
            "name": "permlink",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Unique post identifier containing post''s title and generated number\n"
          },
          {
            "in": "query",
            "name": "page-size",
            "required": false,
            "schema": {
              "type": "integer",
              "default": 100
            },
            "description": "Return max `page-size` operations per page, defaults to `100`"
          },
          {
            "in": "query",
            "name": "data-size-limit",
            "required": false,
            "schema": {
              "type": "integer",
              "default": 200000
            },
            "description": "If the operation length exceeds the `data-size-limit`,\nthe operation body is replaced with a placeholder, defaults to `200000`\n"
          },
          {
            "in": "query",
            "name": "from-block",
            "required": false,
            "schema": {
              "type": "integer",
              "default": 0
            },
            "description": "Lower limit of the block range"
          },
          {
            "in": "query",
            "name": "to-block",
            "required": false,
            "schema": {
              "type": "integer",
              "default": 2147483647
            },
            "description": "Upper limit of the block range"
          },
          {
            "in": "query",
            "name": "start-date",
            "required": false,
            "schema": {
              "type": "string",
              "format": "date-time",
              "default": null
            },
            "description": "Lower limit of the time range"
          },
          {
            "in": "query",
            "name": "end-date",
            "required": false,
            "schema": {
              "type": "string",
              "format": "date-time",
              "default": null
            },
            "description": "Upper limit of the time range"
          }
        ],
        "responses": {
          "200": {
            "description": "Result contains total operations number,\ntotal pages and the list of operations\n\n* Returns `JSON`\n",
            "content": {
              "application/json": {
                "schema": {
                  "type": "string",
                  "x-sql-datatype": "JSON"
                },
                "example": [
                  {
                    "total_operations": 3158,
                    "total_pages": 31,
                    "operations_result": [
                      {
                        "permlink": "bitcoin-payments-accepted-in-20s-soon-to-be-6s",
                        "block_num": 4364560,
                        "operation_id": 18745642461431100,
                        "created_at": "2016-08-24T15:52:00",
                        "trx_hash": null,
                        "operation": {
                          "type": "comment_payout_update_operation",
                          "value": {
                            "author": "blocktrades",
                            "permlink": "bitcoin-payments-accepted-in-20s-soon-to-be-6s"
                          }
                        }
                      },
                      {
                        "permlink": "-blocktrades-adds-support-for-directly-buyingselling-steem",
                        "block_num": 4347061,
                        "operation_id": 18670484828720700,
                        "created_at": "2016-08-24T01:13:48",
                        "trx_hash": null,
                        "operation": {
                          "type": "comment_payout_update_operation",
                          "value": {
                            "author": "blocktrades",
                            "permlink": "-blocktrades-adds-support-for-directly-buyingselling-steem"
                          }
                        }
                      }
                    ]
                  }
                ]
              }
            }
          },
          "404": {
            "description": "No such account in the database"
          }
        }
      }
    },
    "/block-numbers": {
      "get": {
        "tags": [
          "Block-numbers"
        ],
        "summary": "Get block numbers by filters",
        "description": "List the block numbers that match given operation type filter,\naccount name and time/block range in specified order\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_block_by_op(''6'',NULL,''desc'',4999999,5000000);`\n\nREST call example\n* `GET ''https://%1$s/hafbe/block-numbers?operation-types=6&from-block=4999999&to-block5000000''`\n",
        "operationId": "hafbe_endpoints.get_block_by_op",
        "parameters": [
          {
            "in": "query",
            "name": "operation-types",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "List of operations: if the parameter is NULL, all operations will be included\nexample: `18,12`\n"
          },
          {
            "in": "query",
            "name": "account-name",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Filter operations by the account that created them"
          },
          {
            "in": "query",
            "name": "direction",
            "required": false,
            "schema": {
              "$ref": "#/components/schemas/hafbe_types.sort_direction",
              "default": "desc"
            },
            "description": "Sort order:\n\n * `asc` - Ascending, from A to Z or smallest to largest\n\n * `desc` - Descending, from Z to A or largest to smallest\n"
          },
          {
            "in": "query",
            "name": "from-block",
            "required": false,
            "schema": {
              "type": "integer",
              "default": 0
            },
            "description": "Lower limit of the block range"
          },
          {
            "in": "query",
            "name": "to-block",
            "required": false,
            "schema": {
              "type": "integer",
              "default": 2147483647
            },
            "description": "Upper limit of the block range"
          },
          {
            "in": "query",
            "name": "start-date",
            "required": false,
            "schema": {
              "type": "string",
              "format": "date-time",
              "default": null
            },
            "description": "Lower limit of the time range"
          },
          {
            "in": "query",
            "name": "end-date",
            "required": false,
            "schema": {
              "type": "string",
              "format": "date-time",
              "default": null
            },
            "description": "Upper limit of the time range"
          },
          {
            "in": "query",
            "name": "result-limit",
            "required": false,
            "schema": {
              "type": "integer",
              "default": 100
            },
            "description": "Limits the result to `result-limit` records"
          },
          {
            "in": "query",
            "name": "path-filter",
            "required": false,
            "schema": {
              "type": "array",
              "items": {
                "type": "string"
              },
              "x-sql-datatype": "TEXT[]",
              "default": null
            },
            "description": "A parameter specifying the desired value in operation body,\nexample: `value.creator=steem`\n"
          }
        ],
        "responses": {
          "200": {
            "description": "Block number with filtered operations\n\n* Returns array of `hafbe_types.block_by_ops`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hafbe_types.array_of_block_by_ops"
                },
                "example": [
                  {
                    "block_num": 4999999,
                    "op_type_id": [
                      6
                    ]
                  }
                ]
              }
            }
          },
          "404": {
            "description": "No operations in database"
          }
        }
      }
    },
    "/block-numbers/headblock": {
      "get": {
        "tags": [
          "Block-numbers"
        ],
        "summary": "HAF last synced block",
        "description": "Get last block-num in HAF database\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_head_block_num();`\n\nREST call example\n* `GET ''https://%1$s/hafbe/block-numbers/headblock''`\n",
        "operationId": "hafbe_endpoints.get_head_block_num",
        "responses": {
          "200": {
            "description": "Last HAF block\n\n* Returns `INT`\n",
            "content": {
              "application/json": {
                "schema": {
                  "type": "integer"
                },
                "example": 5000000
              }
            }
          },
          "404": {
            "description": "No blocks in the database"
          }
        }
      }
    },
    "/block-numbers/headblock/hafbe": {
      "get": {
        "tags": [
          "Block-numbers"
        ],
        "summary": "Haf_block_explorer''s last synced block",
        "description": "Get last block-num synced by haf_block_explorer\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_hafbe_last_synced_block();`\n\nREST call example\n* `GET ''https://%1$s/hafbe/block-numbers/headblock/hafbe''`\n",
        "operationId": "hafbe_endpoints.get_hafbe_last_synced_block",
        "responses": {
          "200": {
            "description": "Last synced block\n\n* Returns `INT`\n",
            "content": {
              "application/json": {
                "schema": {
                  "type": "integer"
                },
                "example": 5000000
              }
            }
          },
          "404": {
            "description": "No blocks synced"
          }
        }
      }
    },
    "/block-numbers/by-creation-date/{timestamp}": {
      "get": {
        "tags": [
          "Block-numbers"
        ],
        "summary": "Search for last created block for given date",
        "description": "Returns last created block number for given date\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_block_by_time(''2016-06-24T16:05:00'');`\n\nREST call example\n* `GET ''https://%1$s/hafbe/block-numbers/by-creation-date/2016-06-24T16:05:00''`\n",
        "operationId": "hafbe_endpoints.get_block_by_time",
        "parameters": [
          {
            "in": "path",
            "name": "timestamp",
            "required": true,
            "schema": {
              "type": "string",
              "format": "date-time"
            },
            "description": "Given date"
          }
        ],
        "responses": {
          "200": {
            "description": "No blocks created at that time",
            "content": {
              "application/json": {
                "schema": {
                  "type": "integer"
                },
                "example": 2621429
              }
            }
          }
        }
      }
    },
    "/version": {
      "get": {
        "tags": [
          "Other"
        ],
        "summary": "Haf_block_explorer''s version",
        "description": "Get haf_block_explorer''s last commit hash that determinates its version\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_hafbe_version();`\n\nREST call example\n* `GET ''https://%1$s/hafbe/version''`\n",
        "operationId": "hafbe_endpoints.get_hafbe_version",
        "responses": {
          "200": {
            "description": "Haf_block_explorer version\n\n* Returns `TEXT`\n",
            "content": {
              "application/json": {
                "schema": {
                  "type": "string"
                },
                "example": "c2fed8958584511ef1a66dab3dbac8c40f3518f0"
              }
            }
          },
          "404": {
            "description": "App not installed"
          }
        }
      }
    },
    "/input-type/{input-value}": {
      "get": {
        "tags": [
          "Other"
        ],
        "summary": "Get input type",
        "description": "Determines whether the entered value is a block,\nblock hash, transaction hash, or account name\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_input_type(''blocktrades'');`\n      \nREST call example\n* `GET ''https://%1$s/hafbe/input-type/blocktrades''`\n",
        "operationId": "hafbe_endpoints.get_input_type",
        "parameters": [
          {
            "in": "path",
            "name": "input-value",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "Given value"
          }
        ],
        "responses": {
          "200": {
            "description": "Result contains total operations number,\ntotal pages and the list of operations\n\n* Returns `JSON`\n",
            "content": {
              "application/json": {
                "schema": {
                  "type": "string",
                  "x-sql-datatype": "JSON"
                },
                "example": [
                  {
                    "input_type": "account_name",
                    "input_value": "blocktrades"
                  }
                ]
              }
            }
          },
          "404": {
            "description": "Input is not recognized"
          }
        }
      }
    },
    "/operation-type-counts": {
      "get": {
        "tags": [
          "Other"
        ],
        "summary": "Informations about operations in blocks",
        "description": "Lists the counts of operations in result-limit blocks along with their creators. \nIf block-num is not specified, the result includes the counts of operations in the most recent blocks. \n\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_latest_blocks(1);`\n\nREST call example      \n* `GET ''https://%1$s/hafbe/operation-type-counts?result-limit=1''`\n",
        "operationId": "hafbe_endpoints.get_latest_blocks",
        "parameters": [
          {
            "in": "query",
            "name": "block-num",
            "required": false,
            "schema": {
              "type": "integer",
              "default": null
            },
            "description": "Given block number, defaults to `NULL`"
          },
          {
            "in": "query",
            "name": "result-limit",
            "required": false,
            "schema": {
              "type": "integer",
              "default": 20
            },
            "description": "Specifies number of blocks to return starting with head block, defaults to `20`\n"
          }
        ],
        "responses": {
          "200": {
            "description": "Operation counts for each block \n\n* Returns array of `hafbe_types.latest_blocks`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hafbe_types.array_of_latest_blocks"
                },
                "example": [
                  {
                    "block_num": 5000000,
                    "witness": "ihashfury",
                    "ops_count": [
                      {
                        "count": 1,
                        "op_type_id": 64
                      },
                      {
                        "count": 1,
                        "op_type_id": 9
                      },
                      {
                        "count": 1,
                        "op_type_id": 80
                      },
                      {
                        "count": 1,
                        "op_type_id": 5
                      }
                    ]
                  }
                ]
              }
            }
          },
          "404": {
            "description": "No blocks in the database"
          }
        }
      }
    },
    "/global-state": {
      "get": {
        "tags": [
          "Other"
        ],
        "summary": "Informations about block",
        "description": "Lists the parameters of the block provided by the user\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_block(5000000);`\n\nREST call example      \n* `GET ''https://%1$s/hafbe/global-state?block-num=5000000''`\n",
        "operationId": "hafbe_endpoints.get_block",
        "parameters": [
          {
            "in": "query",
            "name": "block-num",
            "required": true,
            "schema": {
              "type": "integer"
            },
            "description": "Given block number"
          }
        ],
        "responses": {
          "200": {
            "description": "Given block''s stats\n\n* Returns `hafbe_types.block`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hafbe_types.block"
                },
                "example": [
                  {
                    "block_num": 5000000,
                    "hash": "004c4b40245ffb07380a393fb2b3d841b76cdaec",
                    "prev": "004c4b3fc6a8735b4ab5433d59f4526e4a042644",
                    "producer_account": "ihashfury",
                    "transaction_merkle_root": "97a8f2b04848b860f1792dc07bf58efcb15aeb8c",
                    "extensions": [],
                    "witness_signature": "1f6aa1c6311c768b5225b115eaf5798e5f1d8338af3970d90899cd5ccbe38f6d1f7676c5649bcca18150cbf8f07c0cc7ec3ae40d5936cfc6d5a650e582ba0f8002",
                    "signing_key": "STM8aUs6SGoEmNYMd3bYjE1UBr6NQPxGWmTqTdBaxJYSx244edSB2",
                    "hbd_interest_rate": 1000,
                    "total_vesting_fund_hive": 149190428013,
                    "total_vesting_shares": 448144916705468350,
                    "total_reward_fund_hive": 66003975,
                    "virtual_supply": 161253662237,
                    "current_supply": 157464400971,
                    "current_hbd_supply": 2413759427,
                    "dhf_interval_ledger": 0,
                    "created_at": "2016-09-15T19:47:21"
                  }
                ]
              }
            }
          },
          "404": {
            "description": "No blocks in the database"
          }
        }
      }
    }
  }
}
$$;
-- openapi-generated-code-end
begin
  return openapi;
end
$_$ language plpgsql;'
, swagger_url);

END
$__$;

RESET ROLE;
