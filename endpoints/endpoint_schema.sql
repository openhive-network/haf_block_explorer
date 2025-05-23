SET ROLE hafbe_owner;

/** openapi
openapi: 3.1.0
info:
  title: HAF Block Explorer
  description: >-
    HAF block explorer is an API for getting information about
    transactions/operations included in Hive blocks, as well as block producer (witness)
    information.
  license:
    name: MIT License
    url: https://opensource.org/license/mit
  version: 1.27.11
externalDocs:
  description: HAF Block Explorer gitlab repository
  url: https://gitlab.syncad.com/hive/haf_block_explorer
tags:
  - name: Block-search
    description: Information about blocks
  - name: Transactions
    description: Information about transactions
  - name: Accounts
    description: Information about accounts
  - name: Witnesses
    description: Information about witnesses
  - name: Other
    description: General API information
servers:
  - url: /hafbe-api
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
      "hafbe_types.comment_type": {
        "type": "string",
        "enum": [
          "post",
          "comment",
          "all"
        ]
      },
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
          "version",
          "feed_updated_at"
        ]
      },
      "hafbe_types.witness": {
        "type": "object",
        "properties": {
          "witness_name": {
            "type": "string",
            "description": "witness''s account name"
          },
          "rank": {
            "type": "integer",
            "description": "the current rank of the witness according to the votes cast on the blockchain. The top 20 witnesses (ranks 1 - 20) will produce blocks each round."
          },
          "url": {
            "type": "string",
            "description": "the witness''s home page"
          },
          "vests": {
            "type": "string",
            "description": "the total weight of votes cast in favor of this witness, expressed in VESTS"
          },
          "votes_daily_change": {
            "type": "string",
            "description": "the increase or decrease in votes for this witness over the last 24 hours, expressed in vests"
          },
          "voters_num": {
            "type": "integer",
            "description": "the number of voters for this witness"
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
            "description": "timestamp when feed was updated"
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
          },
          "last_confirmed_block_num": {
            "type": "integer",
            "description": "the last block number created by the witness"
          },
          "account_creation_fee": {
            "type": "integer",
            "description": "the cost of creating an account."
          }
        }
      },
      "hafbe_types.witness_return": {
        "type": "object",
        "properties": {
          "votes_updated_at": {
            "type": "string",
            "format": "date-time",
            "description": "Time of cache update"
          },
          "witness": {
            "$ref": "#/components/schemas/hafbe_types.witness",
            "description": "Witness parameters"
          }
        }
      },
      "hafbe_types.witnesses_return": {
        "type": "object",
        "properties": {
          "total_witnesses": {
            "type": "integer",
            "description": "Total number of witnesses"
          },
          "total_pages": {
            "type": "integer",
            "description": "Total number of pages"
          },
          "votes_updated_at": {
            "type": "string",
            "format": "date-time",
            "description": "Time of cache update"
          },
          "witnesses": {
            "type": "array",
            "items": {
              "$ref": "#/components/schemas/hafbe_types.witness"
            },
            "description": "List of witness parameters"
          }
        }
      },
      "hafbe_types.witness_voter": {
        "type": "object",
        "properties": {
          "voter_name": {
            "type": "string",
            "description": "account name of the voter"
          },
          "vests": {
            "type": "string",
            "description": "number of vests this voter is directly voting with"
          },
          "account_vests": {
            "type": "string",
            "description": "number of vests in the voter''s account.  if some vests are delegated, they will not be counted in voting"
          },
          "proxied_vests": {
            "type": "string",
            "description": "the number of vests proxied to this account"
          },
          "timestamp": {
            "type": "string",
            "format": "date-time",
            "description": "the time this account last changed its voting power"
          }
        }
      },
      "hafbe_types.witness_voter_history": {
        "type": "object",
        "properties": {
          "total_votes": {
            "type": "integer",
            "description": "Total number of votes"
          },
          "total_pages": {
            "type": "integer",
            "description": "Total number of pages"
          },
          "votes_updated_at": {
            "type": "string",
            "format": "date-time",
            "description": "Time of cache update"
          },
          "voters": {
            "type": "array",
            "items": {
              "$ref": "#/components/schemas/hafbe_types.witness_voter"
            },
            "description": "List of votes results"
          }
        }
      },
      "hafbe_types.witness_votes_history_record": {
        "type": "object",
        "properties": {
          "voter_name": {
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
          "account_vests": {
            "type": "string",
            "description": "number of vests in the voter''s account.  if some vests are delegated, they will not be counted in voting"
          },
          "proxied_vests": {
            "type": "string",
            "description": "the number of vests proxied to this account"
          },
          "timestamp": {
            "type": "string",
            "format": "date-time",
            "description": "the time of the vote change"
          }
        }
      },
      "hafbe_types.witness_votes_history": {
        "type": "object",
        "properties": {
          "votes_updated_at": {
            "type": "string",
            "format": "date-time",
            "description": "Time of cache update"
          },
          "votes_history": {
            "type": "array",
            "items": {
              "$ref": "#/components/schemas/hafbe_types.witness_votes_history_record"
            },
            "description": "List of witness votes"
          }
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
            "description": "an account to which the account has designated as its proxy"
          },
          "recovery_account": {
            "type": "string",
            "description": "an account to which the account has designated as its recovery account"
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
          "pending_claimed_accounts": {
            "type": "integer",
            "description": "pool of prepaid accounts available for user allocation.  These accounts are pre-registered and can be claimed by users as needed"
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
            "type": "array",
            "items": {
              "type": "string"
            },
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
            "type": "array",
            "items": {
              "type": "string"
            },
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
      "hafbe_types.authority_type": {
        "type": "object",
        "properties": {
          "key_auths": {
            "type": "array",
            "items": {
              "type": "string"
            }
          },
          "account_auths": {
            "type": "array",
            "items": {
              "type": "string"
            }
          },
          "weight_threshold": {
            "type": "integer"
          }
        }
      },
      "hafbe_types.account_authority": {
        "type": "object",
        "properties": {
          "owner": {
            "$ref": "#/components/schemas/hafbe_types.authority_type",
            "description": "the most powerful key because it can change any key of an account, including the owner key. Ideally it is meant to be stored offline, and only used to recover a compromised account"
          },
          "active": {
            "$ref": "#/components/schemas/hafbe_types.authority_type",
            "description": "key meant for more sensitive tasks such as transferring funds, power up/down transactions, converting Hive Dollars, voting for witnesses, updating profile details and avatar, and placing a market order"
          },
          "posting": {
            "$ref": "#/components/schemas/hafbe_types.authority_type",
            "description": "key allows accounts to post, comment, edit, vote, reblog and follow or mute other accounts"
          },
          "memo": {
            "type": "string",
            "description": "default key to be used for memo encryption"
          },
          "witness_signing": {
            "type": "string",
            "description": "key used by a witness to sign blocks"
          }
        }
      },
      "hafbe_types.block_range": {
        "type": "object",
        "properties": {
          "from": {
            "type": "integer"
          },
          "to": {
            "type": "integer"
          }
        }
      },
      "hafbe_types.block_operations": {
        "type": "object",
        "properties": {
          "op_type_id": {
            "type": "integer",
            "description": "operation type identifier"
          },
          "op_count": {
            "type": "integer",
            "description": "amount of operations in block"
          }
        }
      },
      "hafbe_types.blocksearch": {
        "type": "object",
        "properties": {
          "block_num": {
            "type": "integer",
            "description": "block number"
          },
          "created_at": {
            "type": "string",
            "format": "date-time",
            "description": "creation date"
          },
          "producer_account": {
            "type": "string",
            "description": "account name of block''s producer"
          },
          "producer_reward": {
            "type": "string",
            "description": "operation type identifier"
          },
          "trx_count": {
            "type": "integer",
            "description": "count of transactions in block"
          },
          "hash": {
            "type": "string",
            "description": "block hash in a blockchain is a unique, fixed-length string generated  by applying a cryptographic hash function to a block''s contents"
          },
          "prev": {
            "type": "string",
            "description": "hash of a previous block"
          },
          "operations": {
            "type": "array",
            "items": {
              "$ref": "#/components/schemas/hafbe_types.block_operations"
            },
            "description": "List of block_operation"
          }
        }
      },
      "hafbe_types.block_history": {
        "type": "object",
        "properties": {
          "total_blocks": {
            "type": "integer",
            "description": "Total number of blocks"
          },
          "total_pages": {
            "type": "integer",
            "description": "Total number of pages"
          },
          "block_range": {
            "$ref": "#/components/schemas/hafbe_types.block_range",
            "description": "Range of blocks that contains the returned pages"
          },
          "blocks_result": {
            "type": "array",
            "items": {
              "$ref": "#/components/schemas/hafbe_types.blocksearch"
            },
            "description": "List of block results"
          }
        }
      },
      "hafbe_types.permlink": {
        "type": "object",
        "properties": {
          "permlink": {
            "type": "string",
            "description": "unique post identifier containing post''s title and generated number"
          },
          "block": {
            "type": "integer",
            "description": "operation block number"
          },
          "trx_id": {
            "type": "string",
            "description": "hash of the transaction"
          },
          "timestamp": {
            "type": "string",
            "format": "date-time",
            "description": "creation date"
          },
          "operation_id": {
            "type": "integer",
            "x-sql-datatype": "TEXT",
            "description": "unique operation identifier with an encoded block number and operation type id"
          }
        }
      },
      "hafbe_types.permlink_history": {
        "type": "object",
        "properties": {
          "total_permlinks": {
            "type": "integer",
            "description": "Total number of permlinks"
          },
          "total_pages": {
            "type": "integer",
            "description": "Total number of pages"
          },
          "block_range": {
            "$ref": "#/components/schemas/hafbe_types.block_range",
            "description": "Range of blocks that contains the returned pages"
          },
          "permlinks_result": {
            "type": "array",
            "items": {
              "$ref": "#/components/schemas/hafbe_types.permlink"
            },
            "description": "List of permlinks"
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
          "operations": {
            "type": "array",
            "items": {
              "$ref": "#/components/schemas/hafbe_types.block_operations"
            },
            "description": "List of block_operation"
          }
        }
      },
      "hafbe_types.array_of_latest_blocks": {
        "type": "array",
        "items": {
          "$ref": "#/components/schemas/hafbe_types.latest_blocks"
        }
      },
      "hafbe_types.input_type_return": {
        "type": "object",
        "properties": {
          "input_type": {
            "type": "string",
            "description": "operation type id"
          },
          "input_value": {
            "type": "array",
            "items": {
              "type": "string"
            },
            "description": "number of operations in the block"
          }
        }
      },
      "hafbe_types.operation_body": {
        "type": "object",
        "x-sql-datatype": "JSON",
        "properties": {
          "type": {
            "type": "string"
          },
          "value": {
            "type": "object"
          }
        }
      },
      "hafbe_types.operation": {
        "type": "object",
        "properties": {
          "op": {
            "$ref": "#/components/schemas/hafah_backend.operation_body",
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
            "description": "the time operation was included in the blockchain"
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
      "hafbe_types.operation_history": {
        "type": "object",
        "properties": {
          "total_operations": {
            "type": "integer",
            "description": "Total number of operations"
          },
          "total_pages": {
            "type": "integer",
            "description": "Total number of pages"
          },
          "operations_result": {
            "type": "array",
            "items": {
              "$ref": "#/components/schemas/hafbe_types.operation"
            },
            "description": "List of operation results"
          }
        }
      },
      "hafbe_types.granularity": {
        "type": "string",
        "enum": [
          "daily",
          "monthly",
          "yearly"
        ]
      },
      "hafbe_types.transaction_stats": {
        "type": "object",
        "properties": {
          "date": {
            "type": "string",
            "format": "date-time",
            "description": "the time transaction was included in the blockchain"
          },
          "trx_count": {
            "type": "integer",
            "description": "amount of transactions"
          },
          "avg_trx": {
            "type": "integer",
            "description": "avarage amount of transactions in block"
          },
          "min_trx": {
            "type": "integer",
            "description": "minimal amount of transactions in block"
          },
          "max_trx": {
            "type": "integer",
            "description": "maximum amount of transactions in block"
          },
          "last_block_num": {
            "type": "integer",
            "description": "last block number in time range"
          }
        }
      },
      "hafbe_types.array_of_transaction_stats": {
        "type": "array",
        "items": {
          "$ref": "#/components/schemas/hafbe_types.transaction_stats"
        }
      }
    }
  },
  "openapi": "3.1.0",
  "info": {
    "title": "HAF Block Explorer",
    "description": "HAF block explorer is an API for getting information about transactions/operations included in Hive blocks, as well as block producer (witness) information.",
    "license": {
      "name": "MIT License",
      "url": "https://opensource.org/license/mit"
    },
    "version": "1.27.11"
  },
  "externalDocs": {
    "description": "HAF Block Explorer gitlab repository",
    "url": "https://gitlab.syncad.com/hive/haf_block_explorer"
  },
  "tags": [
    {
      "name": "Block-search",
      "description": "Information about blocks"
    },
    {
      "name": "Transactions",
      "description": "Information about transactions"
    },
    {
      "name": "Accounts",
      "description": "Information about accounts"
    },
    {
      "name": "Witnesses",
      "description": "Information about witnesses"
    },
    {
      "name": "Other",
      "description": "General API information"
    }
  ],
  "servers": [
    {
      "url": "/hafbe-api"
    }
  ],
  "paths": {
    "/witnesses": {
      "get": {
        "tags": [
          "Witnesses"
        ],
        "summary": "List witnesses",
        "description": "List all witnesses (both active and standby)\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_witnesses(1,2);`\n\nREST call example\n* `GET ''https://%1$s/hafbe-api/witnesses?page-size=2''`\n",
        "operationId": "hafbe_endpoints.get_witnesses",
        "parameters": [
          {
            "in": "query",
            "name": "page",
            "required": false,
            "schema": {
              "type": "integer",
              "default": 1
            },
            "description": "Return page on `page` number, defaults to `1`\n"
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
            "name": "sort",
            "required": false,
            "schema": {
              "$ref": "#/components/schemas/hafbe_types.order_by_witness",
              "default": "votes"
            },
            "description": "Sort key:\n\n * `witness` - the witness name\n\n * `rank` - their current rank (highest weight of votes => lowest rank)\n\n * `url` - the witness url\n\n * `votes` - total number of votes\n\n * `votes_daily_change` - change in `votes` in the last 24 hours\n\n * `voters_num` - total number of voters approving the witness\n\n * `voters_num_daily_change` - change in `voters_num` in the last 24 hours\n\n * `price_feed` - their current published value for the HIVE/HBD price feed\n\n * `feed_updated_at` - feed update timestamp\n\n * `bias` - if HBD is trading at only 0.90 USD on exchanges, the witness might set:\n        base: 0.250 HBD\n        quote: 1.100 HIVE\n      In this case, the bias is 10%%\n\n * `block_size` - the block size they are voting for\n\n * `signing_key` - the witness'' block-signing public key\n\n * `version` - the version of hived the witness is running\n"
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
            "description": "The list of witnesses\n\n* Returns `hafbe_types.witnesses_return`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hafbe_types.witnesses_return"
                },
                "example": {
                  "total_witnesses": 731,
                  "total_pages": 366,
                  "votes_updated_at": "2024-08-29T12:05:08.097875",
                  "witnesses": [
                    {
                      "witness_name": "roadscape",
                      "rank": 1,
                      "url": "https://steemit.com/witness-category/@roadscape/witness-roadscape",
                      "vests": "94172201023355097",
                      "votes_daily_change": "0",
                      "voters_num": 306,
                      "voters_num_daily_change": 0,
                      "price_feed": 0.539,
                      "bias": 0,
                      "feed_updated_at": "2016-09-15T16:07:42",
                      "block_size": 65536,
                      "signing_key": "STM5AS7ZS33pzTf1xbTi8ZUaUeVAZBsD7QXGrA51HvKmvUDwVbFP9",
                      "version": "0.13.0",
                      "missed_blocks": 129,
                      "hbd_interest_rate": 1000,
                      "last_confirmed_block_num": 4999986,
                      "account_creation_fee": 2000
                    },
                    {
                      "witness_name": "arhag",
                      "rank": 2,
                      "url": "https://steemit.com/witness-category/@arhag/witness-arhag",
                      "vests": "91835048921097725",
                      "votes_daily_change": "0",
                      "voters_num": 348,
                      "voters_num_daily_change": 0,
                      "price_feed": 0.536,
                      "bias": 0,
                      "feed_updated_at": "2016-09-15T19:31:18",
                      "block_size": 65536,
                      "signing_key": "STM8kvk4JH2m6ZyHBGNor4qk2Zwdi2MJAjMYUpfqiicCKu7HqAeZh",
                      "version": "0.13.0",
                      "missed_blocks": 61,
                      "hbd_interest_rate": 1000,
                      "last_confirmed_block_num": 4999993,
                      "account_creation_fee": 7000
                    }
                  ]
                }
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
        "summary": "Returns information about a witness.",
        "description": "Returns information about a witness given their account name.\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_witness(''blocktrades'');`\n\nREST call example\n* `GET ''https://%1$s/hafbe-api/witnesses/blocktrades''`\n",
        "operationId": "hafbe_endpoints.get_witness",
        "parameters": [
          {
            "in": "path",
            "name": "account-name",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "witness account name"
          }
        ],
        "responses": {
          "200": {
            "description": "Various witness statistics\n\n* Returns `hafbe_types.witness_return`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hafbe_types.witness_return"
                },
                "example": {
                  "votes_updated_at": "2024-08-29T12:05:08.097875",
                  "witness": {
                    "witness_name": "blocktrades",
                    "rank": 8,
                    "url": "https://blocktrades.us",
                    "vests": "82373419958692803",
                    "votes_daily_change": "0",
                    "voters_num": 263,
                    "voters_num_daily_change": 0,
                    "price_feed": 0.545,
                    "bias": 0,
                    "feed_updated_at": "2016-09-15T16:02:21",
                    "block_size": 65536,
                    "signing_key": "STM4vmVc3rErkueyWNddyGfmjmLs3Rr4i7YJi8Z7gFeWhakXM4nEz",
                    "version": "0.13.0",
                    "missed_blocks": 935,
                    "hbd_interest_rate": 1000,
                    "last_confirmed_block_num": 4999992,
                    "account_creation_fee": 9000
                  }
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
        "description": "Get information about the voters voting for a given witness\n\nSQL example      \n* `SELECT * FROM hafbe_endpoints.get_witness_voters(''blocktrades'',1,2);`\n\nREST call example\n* `GET ''https://%1$s/hafbe-api/witnesses/blocktrades/voters?page-size=2''`\n",
        "operationId": "hafbe_endpoints.get_witness_voters",
        "parameters": [
          {
            "in": "path",
            "name": "account-name",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "witness account name"
          },
          {
            "in": "query",
            "name": "page",
            "required": false,
            "schema": {
              "type": "integer",
              "default": 1
            },
            "description": "Return page on `page` number, defaults to `1`\n"
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
          }
        ],
        "responses": {
          "200": {
            "description": "The number of voters currently voting for this witness\n\n* Returns `hafbe_types.witness_voter_history`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hafbe_types.witness_voter_history"
                },
                "example": {
                  "total_votes": 263,
                  "total_pages": 132,
                  "votes_updated_at": "2024-08-29T12:05:08.097875",
                  "voters": [
                    {
                      "voter_name": "blocktrades",
                      "vests": "13155953611548185",
                      "account_vests": "8172549681941451",
                      "proxied_vests": "4983403929606734",
                      "timestamp": "2016-04-15T02:19:57"
                    },
                    {
                      "voter_name": "dan",
                      "vests": "9928811304950768",
                      "account_vests": "9928811304950768",
                      "proxied_vests": "0",
                      "timestamp": "2016-06-27T12:41:42"
                    }
                  ]
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
    "/witnesses/{account-name}/voters/count": {
      "get": {
        "tags": [
          "Witnesses"
        ],
        "summary": "Get the number of voters for a witness",
        "description": "Get the number of voters for a witness\n\nSQL example      \n* `SELECT * FROM hafbe_endpoints.get_witness_voters_num(''blocktrades'');`\n\nREST call example\n* `GET ''https://%1$s/hafbe-api/witnesses/blocktrades/voters/count''`\n",
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
        "summary": "Get the history of votes for this witness.",
        "description": "Get information about each vote cast for this witness\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_witness_votes_history(''blocktrades'');`\n\nREST call example\n* `GET ''https://%1$s/hafbe-api/witnesses/blocktrades/votes/history?result-limit=2''`\n",
        "operationId": "hafbe_endpoints.get_witness_votes_history",
        "parameters": [
          {
            "in": "path",
            "name": "account-name",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "witness account name"
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
            "name": "from-block",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Lower limit of the block range, can be represented either by a block-number (integer) or a timestamp (in the format YYYY-MM-DD HH:MI:SS).\n\nThe provided `timestamp` will be converted to a `block-num` by finding the first block \nwhere the block''s `created_at` is more than or equal to the given `timestamp` (i.e. `block''s created_at >= timestamp`).\n\nThe function will interpret and convert the input based on its format, example input:\n\n* `2016-09-15 19:47:21`\n\n* `5000000`\n"
          },
          {
            "in": "query",
            "name": "to-block",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Similar to the from-block parameter, can either be a block-number (integer) or a timestamp (formatted as YYYY-MM-DD HH:MI:SS). \n\nThe provided `timestamp` will be converted to a `block-num` by finding the first block \nwhere the block''s `created_at` is less than or equal to the given `timestamp` (i.e. `block''s created_at <= timestamp`).\n\nThe function will convert the value depending on its format, example input:\n\n* `2016-09-15 19:47:21`\n\n* `5000000`\n"
          }
        ],
        "responses": {
          "200": {
            "description": "The number of voters currently voting for this witness\n\n* Returns `hafbe_types.witness_votes_history`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hafbe_types.witness_votes_history"
                },
                "example": {
                  "votes_updated_at": "2024-08-29T12:05:08.097875",
                  "votes_history": [
                    {
                      "voter_name": "jeremyfromwi",
                      "approve": true,
                      "vests": "441156952466",
                      "account_vests": "441156952466",
                      "proxied_vests": "0",
                      "timestamp": "2016-09-15T07:07:15"
                    },
                    {
                      "voter_name": "cryptomental",
                      "approve": true,
                      "vests": "686005633844",
                      "account_vests": "686005633844",
                      "proxied_vests": "0",
                      "timestamp": "2016-09-15T07:00:51"
                    }
                  ]
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
    "/accounts/{account-name}": {
      "get": {
        "tags": [
          "Accounts"
        ],
        "summary": "Get information about an account including Hive token balances.",
        "description": "Get account''s balances and parameters\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_account(''blocktrades'');`\n\nREST call example\n* `GET ''https://%1$s/hafbe-api/accounts/blocktrades''`\n",
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
                "example": {
                  "id": 440,
                  "name": "blocktrades",
                  "can_vote": true,
                  "mined": true,
                  "proxy": "",
                  "recovery_account": "steem",
                  "last_account_recovery": "1970-01-01T00:00:00",
                  "created": "2016-03-30T00:04:36",
                  "reputation": 69,
                  "pending_claimed_accounts": 0,
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
                  "proxied_vsf_votes": [
                    "4983403929606734",
                    "0",
                    "0",
                    "0"
                  ],
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
        "summary": "Get account''s owner, active, posting, memo and witness signing authorities",
        "description": "Get information about account''s owner, active, posting, memo and witness signing authorities.\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_account_authority(''blocktrades'');`\n\nREST call example\n* `GET ''https://%1$s/hafbe-api/accounts/blocktrades/authority''` \n",
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
                "example": {
                  "owner": {
                    "key_auths": [
                      [
                        "STM7WdrxF6iuSiHUB4maoLGXXBKXbqAJ9AZbzACX1MPK2AkuCh23S",
                        "1"
                      ]
                    ],
                    "account_auths": [],
                    "weight_threshold": 1
                  },
                  "active": {
                    "key_auths": [
                      [
                        "STM5vgGoHBrUuDCspAPYi3dLwSyistyrz61NWkZNUAXAifZJaDLPF",
                        "1"
                      ]
                    ],
                    "account_auths": [],
                    "weight_threshold": 1
                  },
                  "posting": {
                    "key_auths": [
                      [
                        "STM5SaNVKJgy6ghnkNoMAprTxSDG55zps21Bo8qe1rnHmwAR4LzzC",
                        "1"
                      ]
                    ],
                    "account_auths": [],
                    "weight_threshold": 1
                  },
                  "memo": "STM7EAUbNf1CdTrMbydPoBTRMG4afXCoAErBJYevhgne6zEP6rVBT",
                  "witness_signing": "STM4vmVc3rErkueyWNddyGfmjmLs3Rr4i7YJi8Z7gFeWhakXM4nEz"
                }
              }
            }
          },
          "404": {
            "description": "No such account in the database"
          }
        }
      }
    },
    "/accounts/{account-name}/comment-permlinks": {
      "get": {
        "tags": [
          "Accounts"
        ],
        "summary": "Get comment permlinks for an account.",
        "description": "List comment permlinks of root posts or comments for an account.\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_comment_permlinks(''blocktrades'',''post'',1,2,''4000000'',''4800000'');`\n\nREST call example\n* `GET ''https://%1$s/hafbe-api/accounts/blocktrades/comment-permlinks?comment-type=post&page-size=2&from-block=4000000&to-block=4800000''`\n",
        "operationId": "hafbe_endpoints.get_comment_permlinks",
        "parameters": [
          {
            "in": "path",
            "name": "account-name",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "Account to get operations for"
          },
          {
            "in": "query",
            "name": "comment-type",
            "required": false,
            "schema": {
              "$ref": "#/components/schemas/hafbe_types.comment_type",
              "default": "all"
            },
            "description": "Sort order:\n\n * `post`    - permlinks related to root posts\n\n * `comment` - permlinks related to comments \n\n * `all`     - both, posts and comments\n"
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
            "name": "from-block",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Lower limit of the block range, can be represented either by a block-number (integer) or a timestamp (in the format YYYY-MM-DD HH:MI:SS).\n\nThe provided `timestamp` will be converted to a `block-num` by finding the first block \nwhere the block''s `created_at` is more than or equal to the given `timestamp` (i.e. `block''s created_at >= timestamp`).\n\nThe function will interpret and convert the input based on its format, example input:\n\n* `2016-09-15 19:47:21`\n\n* `5000000`\n"
          },
          {
            "in": "query",
            "name": "to-block",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Similar to the from-block parameter, can either be a block-number (integer) or a timestamp (formatted as YYYY-MM-DD HH:MI:SS). \n\nThe provided `timestamp` will be converted to a `block-num` by finding the first block \nwhere the block''s `created_at` is less than or equal to the given `timestamp` (i.e. `block''s created_at <= timestamp`).\n\nThe function will convert the value depending on its format, example input:\n\n* `2016-09-15 19:47:21`\n\n* `5000000`\n"
          }
        ],
        "responses": {
          "200": {
            "description": "Result contains total number of operations,\ntotal pages, and the list of operations.\n\n* Returns `hafbe_types.permlink_history`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hafbe_types.permlink_history"
                },
                "example": {
                  "total_permlinks": 3,
                  "total_pages": 2,
                  "block_range": {
                    "from": 4000000,
                    "to": 4800000
                  },
                  "permlinks_result": [
                    {
                      "permlink": "witness-report-for-blocktrades-for-last-week-of-august",
                      "block": 4575065,
                      "trx_id": "d35590b9690ee8aa4b572901d62bc6263953346a",
                      "timestamp": "2016-09-01T00:18:51",
                      "operation_id": "19649754552074241"
                    },
                    {
                      "permlink": "blocktrades-witness-report-for-3rd-week-of-august",
                      "block": 4228346,
                      "trx_id": "bdcd754eb66f18eac11322310ae7ece1e951c08c",
                      "timestamp": "2016-08-19T21:27:00",
                      "operation_id": "18160607786173953"
                    }
                  ]
                }
              }
            }
          },
          "404": {
            "description": "No such account in the database"
          }
        }
      }
    },
    "/accounts/{account-name}/operations/comments/{permlink}": {
      "get": {
        "tags": [
          "Accounts"
        ],
        "summary": "Get comment-related operations for an author-permlink.",
        "description": "List operations related to account. Optionally filtered by permlink,\ntime/blockrange, and specific comment-related operations.\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_comment_operations(''blocktrades'',''blocktrades-witness-report-for-3rd-week-of-august'',''0'',1,3);`\n\nREST call example\n* `GET ''https://%1$s/hafbe-api/accounts/blocktrades/operations/comments/blocktrades-witness-report-for-3rd-week-of-august?page-size=3&operation-types=0''`\n",
        "operationId": "hafbe_endpoints.get_comment_operations",
        "parameters": [
          {
            "in": "path",
            "name": "account-name",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "Account to get operations for"
          },
          {
            "in": "path",
            "name": "permlink",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "Unique post identifier containing post''s title and generated number\n"
          },
          {
            "in": "query",
            "name": "operation-types",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "List of operation types to include. If NULL, all comment operation types will be included.\ncomment-related operation type ids: `0, 1, 17, 19, 51, 52, 53, 61, 63, 72, 73`\n"
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
            "name": "direction",
            "required": false,
            "schema": {
              "$ref": "#/components/schemas/hafbe_types.sort_direction",
              "default": "asc"
            },
            "description": "Sort order:\n\n * `asc` - Ascending, from A to Z or smallest to largest\n\n * `desc` - Descending, from Z to A or largest to smallest\n"
          },
          {
            "in": "query",
            "name": "data-size-limit",
            "required": false,
            "schema": {
              "type": "integer",
              "default": 200000
            },
            "description": "If the operation length exceeds the `data-size-limit`,\nthe operation body is replaced with a placeholder (defaults to `200000`).\n"
          }
        ],
        "responses": {
          "200": {
            "description": "Result contains total number of operations,\ntotal pages, and the list of operations.\n\n* Returns `hafbe_types.operation_history `\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hafbe_types.operation_history"
                },
                "example": {
                  "total_operations": 350,
                  "total_pages": 117,
                  "operations_result": [
                    {
                      "op": {
                        "type": "vote_operation",
                        "value": {
                          "voter": "blocktrades",
                          "author": "blocktrades",
                          "weight": 10000,
                          "permlink": "blocktrades-witness-report-for-3rd-week-of-august"
                        }
                      },
                      "block": 4228228,
                      "trx_id": "2bbeb7513e49cb169d4fe446ff980f2102f7210a",
                      "op_pos": 1,
                      "op_type_id": 0,
                      "timestamp": "2016-08-19T21:21:03",
                      "virtual_op": false,
                      "operation_id": "18160100980032256",
                      "trx_in_block": 1
                    },
                    {
                      "op": {
                        "type": "vote_operation",
                        "value": {
                          "voter": "murh",
                          "author": "blocktrades",
                          "weight": 3301,
                          "permlink": "blocktrades-witness-report-for-3rd-week-of-august"
                        }
                      },
                      "block": 4228239,
                      "trx_id": "e06bc7ad9c51a974ee2bd673e8fa4b4f7018bc18",
                      "op_pos": 0,
                      "op_type_id": 0,
                      "timestamp": "2016-08-19T21:21:36",
                      "virtual_op": false,
                      "operation_id": "18160148224672256",
                      "trx_in_block": 1
                    },
                    {
                      "op": {
                        "type": "vote_operation",
                        "value": {
                          "voter": "weenis",
                          "author": "blocktrades",
                          "weight": 10000,
                          "permlink": "blocktrades-witness-report-for-3rd-week-of-august"
                        }
                      },
                      "block": 4228240,
                      "trx_id": "c5a07b2a069db3ac9faffe0c5a6c6296ef3e78c5",
                      "op_pos": 0,
                      "op_type_id": 0,
                      "timestamp": "2016-08-19T21:21:39",
                      "virtual_op": false,
                      "operation_id": "18160152519641600",
                      "trx_in_block": 5
                    }
                  ]
                }
              }
            }
          },
          "404": {
            "description": "No such account in the database"
          }
        }
      }
    },
    "/block-search": {
      "get": {
        "tags": [
          "Block-search"
        ],
        "summary": "List block stats that match operation type filter, account name, and time/block range.",
        "description": "List the block stats that match given operation type filter,\naccount name and time/block range in specified order\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_block_by_op(NULL,NULL,NULL,5);`\n\nREST call example\n* `GET ''https://%1$s/hafbe-api/block-search?page-size=5''`\n",
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
            "description": "List of operations: if the parameter is NULL, all operations will be included.\nexample: `18,12`\n"
          },
          {
            "in": "query",
            "name": "account-name",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Filter operations by the account that created them."
          },
          {
            "in": "query",
            "name": "page",
            "required": false,
            "schema": {
              "type": "integer",
              "default": null
            },
            "description": "Return page on `page` number, defaults to `NULL`"
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
              "type": "string",
              "default": null
            },
            "description": "Lower limit of the block range, can be represented either by a block-number (integer) or a timestamp (in the format YYYY-MM-DD HH:MI:SS).\n\nThe provided `timestamp` will be converted to a `block-num` by finding the first block \nwhere the block''s `created_at` is more than or equal to the given `timestamp` (i.e. `block''s created_at >= timestamp`).\n\nThe function will interpret and convert the input based on its format, example input:\n\n* `2016-09-15 19:47:21`\n\n* `5000000`\n"
          },
          {
            "in": "query",
            "name": "to-block",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Similar to the from-block parameter, can either be a block-number (integer) or a timestamp (formatted as YYYY-MM-DD HH:MI:SS). \n\nThe provided `timestamp` will be converted to a `block-num` by finding the first block \nwhere the block''s `created_at` is less than or equal to the given `timestamp` (i.e. `block''s created_at <= timestamp`).\n\nThe function will convert the value depending on its format, example input:\n\n* `2016-09-15 19:47:21`\n\n* `5000000`\n"
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
            "description": "A parameter specifying the desired value in operation body,\nexample: `value.creator=alpha`\n"
          }
        ],
        "responses": {
          "200": {
            "description": "Block number with filtered operations\n\n* Returns `hafbe_types.block_history`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hafbe_types.block_history"
                },
                "example": {
                  "total_blocks": 5000000,
                  "total_pages": 1000000,
                  "block_range": {
                    "from": 1,
                    "to": 5000000
                  },
                  "blocks_result": [
                    {
                      "block_num": 5000000,
                      "created_at": "2016-09-15T19:47:21",
                      "producer_account": "ihashfury",
                      "producer_reward": "3003845513",
                      "trx_count": 2,
                      "hash": "004c4b40245ffb07380a393fb2b3d841b76cdaec",
                      "prev": "004c4b3fc6a8735b4ab5433d59f4526e4a042644",
                      "operations": [
                        {
                          "op_type_id": 5,
                          "op_count": 1
                        },
                        {
                          "op_type_id": 9,
                          "op_count": 1
                        },
                        {
                          "op_type_id": 64,
                          "op_count": 1
                        },
                        {
                          "op_type_id": 80,
                          "op_count": 1
                        }
                      ]
                    },
                    {
                      "block_num": 4999999,
                      "created_at": "2016-09-15T19:47:18",
                      "producer_account": "smooth.witness",
                      "producer_reward": "3003846056",
                      "trx_count": 4,
                      "hash": "004c4b3fc6a8735b4ab5433d59f4526e4a042644",
                      "prev": "004c4b3e03ea2eac2494790786bfb9e41a8669d9",
                      "operations": [
                        {
                          "op_type_id": 0,
                          "op_count": 1
                        },
                        {
                          "op_type_id": 6,
                          "op_count": 2
                        },
                        {
                          "op_type_id": 30,
                          "op_count": 1
                        },
                        {
                          "op_type_id": 64,
                          "op_count": 1
                        },
                        {
                          "op_type_id": 72,
                          "op_count": 1
                        },
                        {
                          "op_type_id": 78,
                          "op_count": 1
                        },
                        {
                          "op_type_id": 85,
                          "op_count": 2
                        }
                      ]
                    },
                    {
                      "block_num": 4999998,
                      "created_at": "2016-09-15T19:47:15",
                      "producer_account": "steemed",
                      "producer_reward": "3003846904",
                      "trx_count": 2,
                      "hash": "004c4b3e03ea2eac2494790786bfb9e41a8669d9",
                      "prev": "004c4b3d6c34ebe3eb75dad04ce0a13b5f8a08cf",
                      "operations": [
                        {
                          "op_type_id": 0,
                          "op_count": 1
                        },
                        {
                          "op_type_id": 1,
                          "op_count": 1
                        },
                        {
                          "op_type_id": 64,
                          "op_count": 1
                        },
                        {
                          "op_type_id": 72,
                          "op_count": 1
                        }
                      ]
                    },
                    {
                      "block_num": 4999997,
                      "created_at": "2016-09-15T19:47:12",
                      "producer_account": "clayop",
                      "producer_reward": "3003847447",
                      "trx_count": 4,
                      "hash": "004c4b3d6c34ebe3eb75dad04ce0a13b5f8a08cf",
                      "prev": "004c4b3c51ee947feceeb1812702816114aea6e4",
                      "operations": [
                        {
                          "op_type_id": 0,
                          "op_count": 2
                        },
                        {
                          "op_type_id": 2,
                          "op_count": 1
                        },
                        {
                          "op_type_id": 5,
                          "op_count": 1
                        },
                        {
                          "op_type_id": 61,
                          "op_count": 1
                        },
                        {
                          "op_type_id": 64,
                          "op_count": 1
                        },
                        {
                          "op_type_id": 72,
                          "op_count": 2
                        }
                      ]
                    },
                    {
                      "block_num": 4999996,
                      "created_at": "2016-09-15T19:47:09",
                      "producer_account": "riverhead",
                      "producer_reward": "3003847991",
                      "trx_count": 2,
                      "hash": "004c4b3c51ee947feceeb1812702816114aea6e4",
                      "prev": "004c4b3bd268694ea02f24de50c50c9e7a831e60",
                      "operations": [
                        {
                          "op_type_id": 6,
                          "op_count": 2
                        },
                        {
                          "op_type_id": 64,
                          "op_count": 1
                        },
                        {
                          "op_type_id": 85,
                          "op_count": 2
                        }
                      ]
                    }
                  ]
                }
              }
            }
          },
          "404": {
            "description": "No operations in database"
          }
        }
      }
    },
    "/transaction-statistics": {
      "get": {
        "tags": [
          "Transactions"
        ],
        "summary": "Aggregated transaction statistics",
        "description": "History of amount of transactions per day, month or year.\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_transaction_statistics();`\n\nREST call example\n* `GET ''https://%1$s/hafbe-api/transaction-statistics''`\n",
        "operationId": "hafbe_endpoints.get_transaction_statistics",
        "parameters": [
          {
            "in": "query",
            "name": "granularity",
            "required": false,
            "schema": {
              "$ref": "#/components/schemas/hafbe_types.granularity",
              "default": "yearly"
            },
            "description": "granularity types:\n\n* daily\n\n* monthly\n\n* yearly\n"
          },
          {
            "in": "query",
            "name": "direction",
            "required": false,
            "schema": {
              "$ref": "#/components/schemas/hafbe_types.sort_direction",
              "default": "desc"
            },
            "description": "Sort order:\n\n * `asc` - Ascending, from oldest to newest \n\n * `desc` - Descending, from newest to oldest \n"
          },
          {
            "in": "query",
            "name": "from-block",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Lower limit of the block range, can be represented either by a block-number (integer) or a timestamp (in the format YYYY-MM-DD HH:MI:SS).\n\nThe provided `timestamp` will be converted to a `block-num` by finding the first block \nwhere the block''s `created_at` is more than or equal to the given `timestamp` (i.e. `block''s created_at >= timestamp`).\n\nThe function will interpret and convert the input based on its format, example input:\n\n* `2016-09-15 19:47:21`\n\n* `5000000`\n"
          },
          {
            "in": "query",
            "name": "to-block",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Similar to the from-block parameter, can either be a block-number (integer) or a timestamp (formatted as YYYY-MM-DD HH:MI:SS). \n\nThe provided `timestamp` will be converted to a `block-num` by finding the first block \nwhere the block''s `created_at` is less than or equal to the given `timestamp` (i.e. `block''s created_at <= timestamp`).\n\nThe function will convert the value depending on its format, example input:\n\n* `2016-09-15 19:47:21`\n\n* `5000000`\n"
          }
        ],
        "responses": {
          "200": {
            "description": "Balance change\n\n* Returns array of `hafbe_types.transaction_stats`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hafbe_types.array_of_transaction_stats"
                },
                "example": [
                  {
                    "date": "2016-12-31T23:59:59",
                    "trx_count": 6961192,
                    "avg_trx": 1,
                    "min_trx": 0,
                    "max_trx": 89,
                    "last_block_num": 5000000
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
    "/version": {
      "get": {
        "tags": [
          "Other"
        ],
        "summary": "Get Haf_block_explorer''s version",
        "description": "Get haf_block_explorer''s last commit hash (versions set by by hash value).\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_hafbe_version();`\n\nREST call example\n* `GET ''https://%1$s/hafbe-api/version''`\n",
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
    "/last-synced-block": {
      "get": {
        "tags": [
          "Other"
        ],
        "summary": "Get last block number synced by haf_block_explorer",
        "description": "Get the block number of the last block synced by haf_block_explorer.\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_hafbe_last_synced_block();`\n\nREST call example\n* `GET ''https://%1$s/hafbe-api/last-synced-block''`\n",
        "operationId": "hafbe_endpoints.get_hafbe_last_synced_block",
        "responses": {
          "200": {
            "description": "Last synced block by Haf_block_explorer\n\n* Returns `INT`\n",
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
    "/input-type/{input-value}": {
      "get": {
        "tags": [
          "Other"
        ],
        "summary": "Determines object type of input-value.",
        "description": "Determines whether the entered value is a block,\nblock hash, transaction hash, or account name.\nThis method is very specific to block explorer UIs.\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_input_type(''blocktrades'');`\n      \nREST call example\n* `GET ''https://%1$s/hafbe-api/input-type/blocktrades''`\n",
        "operationId": "hafbe_endpoints.get_input_type",
        "parameters": [
          {
            "in": "path",
            "name": "input-value",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "Object type to be identified."
          }
        ],
        "responses": {
          "200": {
            "description": "Result contains total operations number,\ntotal pages and the list of operations\n\n* Returns `hafbe_types.input_type_return `\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hafbe_types.input_type_return"
                },
                "example": {
                  "input_type": "account_name",
                  "input_value": [
                    "blocktrades"
                  ]
                }
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
        "summary": "Returns histogram of operation types in blocks.",
        "description": "Lists the counts of operations in result-limit blocks along with their creators. \nIf block-num is not specified, the result includes the counts of operations in the most recent blocks.\n\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_latest_blocks(1);`\n\nREST call example      \n* `GET ''https://%1$s/hafbe-api/operation-type-counts?result-limit=1''`\n",
        "operationId": "hafbe_endpoints.get_latest_blocks",
        "parameters": [
          {
            "in": "query",
            "name": "block-num",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Given block, can be represented either by a `block-num` (integer) or a `timestamp` (in the format `YYYY-MM-DD HH:MI:SS`),\n\nThe provided `timestamp` will be converted to a `block-num` by finding the first block \nwhere the block''s `created_at` is less than or equal to the given `timestamp` (i.e. `block''s created_at <= timestamp`). \n\nThe function will interpret and convert the input based on its format, example input:\n\n* `2016-09-15 19:47:21`\n\n* `5000000`\n"
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
                    "operations": [
                      {
                        "op_count": 1,
                        "op_type_id": 64
                      },
                      {
                        "op_count": 1,
                        "op_type_id": 9
                      },
                      {
                        "op_count": 1,
                        "op_type_id": 80
                      },
                      {
                        "op_count": 1,
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
