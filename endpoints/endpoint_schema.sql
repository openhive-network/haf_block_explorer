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
  - name: Blocks
    description: Informations about blocks
  - name: Block-numbers
    description: Informations about block numbers
  - name: Transactions
    description: Informations about transactions
  - name: Operations
    description: Informations about operations
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

create or replace function hafbe_endpoints.root() returns json as $_$
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
          "feed_age",
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
            "description": "the witness's home page"
          },
          "vests": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
            "description": "the total weight of votes cast in favor of this witness, expressed in VESTS"
          },
          "vests_hive_power": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
            "description": "the total weight of votes cast in favor of this witness, expressed in HIVE power, at the current ratio"
          },
          "votes_daily_change": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
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
            "description": "When setting the price feed, you specify the base and quote. Typically, if market conditions are stable and, for example, HBD is trading at 0.25 USD on exchanges, a witness would set:\n  base: 0.250 HBD\n  quote: 1.000 HIVE\n(This indicates that one HIVE costs 0.25 HBD.) However, if the peg is not maintained and HBD does not equal 1 USD (either higher or lower), the witness can adjust the feed accordingly. For instance, if HBD is trading at only 0.90 USD on exchanges, the witness might set:\n  base: 0.250 HBD\n  quote: 1.100 HIVE\nIn this case, the bias is 10%"
          },
          "feed_age": {
            "type": "string",
            "x-sql-datatype": "INTERVAL",
            "description": "how old the witness price feed is (as a string formatted hh:mm:ss.ssssss)"
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
            "description": "the number of blocks the witness should have generated but didn't (over the entire lifetime of the blockchain)"
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
            "type": "integer",
            "x-sql-datatype": "BIGINT",
            "description": "number of vests this voter is directly voting with"
          },
          "votes_hive_power": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
            "description": "number of vests this voter is directly voting with, expressed in HIVE power, at the current ratio"
          },
          "account_vests": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
            "description": "number of vests in the voter's account.  if some vests are delegated, they will not be counted in voting"
          },
          "account_hive_power": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
            "description": "number of vests in the voter's account, expressed in HIVE power, at the current ratio.  if some vests are delegated, they will not be counted in voting"
          },
          "proxied_vests": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
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
            "type": "integer",
            "x-sql-datatype": "BIGINT",
            "description": "number of vests this voter is directly voting with"
          },
          "votes_hive_power": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
            "description": "number of vests this voter is directly voting with, expressed in HIVE power, at the current ratio"
          },
          "account_vests": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
            "description": "number of vests in the voter's account.  if some vests are delegated, they will not be counted in voting"
          },
          "account_hive_power": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
            "description": "number of vests in the voter's account, expressed in HIVE power, at the current ratio.  if some vests are delegated, they will not be counted in voting"
          },
          "proxied_vests": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
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
            "description": "account's identification number"
          },
          "name": {
            "type": "string",
            "description": "account's name"
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
            "description": "numerical rating of the user  based on upvotes and downvotes on user's posts"
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
            "description": "account's HIVE balance"
          },
          "vesting_shares": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
            "description": "account's VEST balance"
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
            "description": "number representing how many payouts are pending  from user's saving balance "
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
            "type": "integer",
            "x-sql-datatype": "BIGINT",
            "description": "not yet claimed VESTS  stored in vest reward balance"
          },
          "reward_vesting_hive": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
            "description": "the reward vesting balance, denominated in HIVE,  is determined by the prevailing HIVE price at the time of reward reception"
          },
          "posting_rewards": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
            "description": "rewards obtained by posting and commenting expressed in VEST"
          },
          "curation_rewards": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
            "description": "curator's reward expressed in VEST"
          },
          "delegated_vesting_shares": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
            "description": "VESTS delegated to another user,  account's power is lowered by delegated VESTS"
          },
          "received_vesting_shares": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
            "description": "VESTS received from another user,  account's power is increased by received VESTS"
          },
          "proxied_vsf_votes": {
            "type": "string",
            "x-sql-datatype": "JSON",
            "description": "recursive proxy of VESTS "
          },
          "withdrawn": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
            "description": "the total VESTS already withdrawn from active withdrawals"
          },
          "vesting_withdraw_rate": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
            "description": "received until the withdrawal is complete,  with each installment amounting to 1/13 of the withdrawn total"
          },
          "to_withdraw": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
            "description": "the remaining total VESTS needed to complete withdrawals"
          },
          "withdraw_routes": {
            "type": "integer",
            "description": "list of account receiving the part of a withdrawal"
          },
          "delayed_vests": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
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
            "description": "unique post identifier containing post's title and generated number"
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
          },
          "is_modified": {
            "type": "boolean",
            "description": "true if operation body was modified with body placeholder due to its lenght"
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
            "x-sql-datatype": "bytea",
            "description": "block hash in a blockchain is a unique, fixed-length string generated  by applying a cryptographic hash function to a block's contents"
          },
          "prev": {
            "type": "string",
            "x-sql-datatype": "bytea",
            "description": "hash of a previous block"
          },
          "producer_account": {
            "type": "string",
            "description": "account name of block's producer"
          },
          "transaction_merkle_root": {
            "type": "string",
            "x-sql-datatype": "bytea",
            "description": "single hash representing the combined hashes of all transactions in a block"
          },
          "extensions": {
            "type": "string",
            "x-sql-datatype": "JSONB",
            "description": "various additional data/parameters related to the subject at hand. Most often, there's nothing specific, but it's a mechanism for extending various functionalities where something might appear in the future."
          },
          "witness_signature": {
            "type": "string",
            "x-sql-datatype": "bytea",
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
          },
          "age": {
            "type": "string",
            "x-sql-datatype": "INTERVAL",
            "description": "the time that has elapsed since the block was created."
          }
        }
      },
      "hafbe_types.block_raw": {
        "type": "object",
        "properties": {
          "previous": {
            "type": "string",
            "x-sql-datatype": "bytea",
            "description": "hash of a previous block"
          },
          "timestamp": {
            "type": "string",
            "format": "date-time",
            "description": "the timestamp when the block was created"
          },
          "witness": {
            "type": "string",
            "x-sql-datatype": "VARCHAR",
            "description": "account name of block's producer"
          },
          "transaction_merkle_root": {
            "type": "string",
            "x-sql-datatype": "bytea",
            "description": "single hash representing the combined hashes of all transactions in a block"
          },
          "extensions": {
            "type": "string",
            "x-sql-datatype": "JSONB",
            "description": "various additional data/parameters related to the subject at hand. Most often, there's nothing specific, but it's a mechanism for extending various functionalities where something might appear in the future."
          },
          "witness_signature": {
            "type": "string",
            "x-sql-datatype": "bytea",
            "description": "witness signature"
          },
          "transactions": {
            "type": "string",
            "x-sql-datatype": "JSONB",
            "description": "list of transactions"
          },
          "block_id": {
            "type": "string",
            "x-sql-datatype": "bytea",
            "description": "the block_id from the block header"
          },
          "signing_key": {
            "type": "string",
            "description": "it refers to the public key of the witness used for signing blocks and other witness operations"
          },
          "transaction_ids": {
            "type": "array",
            "items": {
              "type": "string"
            },
            "x-sql-datatype": "bytea[]",
            "description": "list of transaction's hashes that occured in given block"
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
      "hafbe_types.op_count_in_block": {
        "type": "object",
        "properties": {
          "op_type_id": {
            "type": "integer",
            "description": "operation id"
          },
          "count": {
            "type": "integer",
            "x-sql-datatype": "BIGINT",
            "description": "number of the operations in block"
          }
        }
      },
      "hafbe_types.array_of_op_count_in_block": {
        "type": "array",
        "items": {
          "$ref": "#/components/schemas/hafbe_types.op_count_in_block"
        }
      },
      "hafbe_types.op_types": {
        "type": "object",
        "properties": {
          "op_type_id": {
            "type": "integer",
            "description": "operation type id"
          },
          "operation_name": {
            "type": "string",
            "description": "operation type name"
          },
          "is_virtual": {
            "type": "boolean",
            "description": "true if operation is virtual"
          }
        }
      },
      "hafbe_types.array_of_op_types": {
        "type": "array",
        "items": {
          "$ref": "#/components/schemas/hafbe_types.op_types"
        }
      },
      "hafbe_types.operation": {
        "type": "object",
        "properties": {
          "operation_id": {
            "type": "string",
            "description": "unique operation identifier with an encoded block number and operation type id"
          },
          "block_num": {
            "type": "integer",
            "description": "operation block number"
          },
          "trx_in_block": {
            "type": "integer",
            "x-sql-datatype": "SMALLINT",
            "description": "transaction identifier that indicates its sequence number in block"
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
          "operation": {
            "type": "string",
            "x-sql-datatype": "JSONB",
            "description": "operation body"
          },
          "virtual_op": {
            "type": "boolean",
            "description": "true if is a virtual operation"
          },
          "timestamp": {
            "type": "string",
            "format": "date-time",
            "description": "creation date"
          },
          "age": {
            "type": "string",
            "x-sql-datatype": "INTERVAL",
            "description": "how old is the operation"
          },
          "is_modified": {
            "type": "boolean",
            "description": "true if operation body was modified with body placeholder due to its lenght"
          }
        }
      },
      "hafbe_types.transaction": {
        "type": "object",
        "properties": {
          "transaction_json": {
            "type": "string",
            "x-sql-datatype": "JSON",
            "description": "contents of the transaction"
          },
          "transaction_id": {
            "type": "string",
            "description": "hash of the transaction"
          },
          "block_num": {
            "type": "integer",
            "description": "number of block the transaction was in"
          },
          "transaction_num": {
            "type": "integer",
            "description": "number of the transaction in block"
          },
          "timestamp": {
            "type": "string",
            "format": "date-time",
            "description": "the time of the transaction was made"
          },
          "age": {
            "type": "string",
            "x-sql-datatype": "INTERVAL",
            "description": "how old is the transaction"
          }
        }
      },
      "hafbe_types.array_of_text_array": {
        "type": "array",
        "items": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "x-sql-datatype": "TEXT[]"
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
      "name": "Blocks",
      "description": "Informations about blocks"
    },
    {
      "name": "Block-numbers",
      "description": "Informations about block numbers"
    },
    {
      "name": "Transactions",
      "description": "Informations about transactions"
    },
    {
      "name": "Operations",
      "description": "Informations about operations"
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
        "description": "List all witnesses (both active and standby)\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_witnesses();`\n* `SELECT * FROM hafbe_endpoints.get_witnesses(10);`\n\nREST call example\n* `GET https://{hafbe-host}/hafbe/witnesses`\n* `GET https://{hafbe-host}/hafbe/witnesses?result-limit=10`\n",
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
            "description": "Sort order:\n\n * `witness` - the witness' name\n\n * `rank` - their current rank (highest weight of votes => lowest rank)\n\n * `url` - the witness' url\n\n * `votes` - total number of votes\n\n * `votes_daily_change` - change in `votes` in the last 24 hours\n\n * `voters_num` - total number of voters approving the witness\n\n * `voters_num_daily_change` - change in `voters_num` in the last 24 hours\n\n * `price_feed` - their current published value for the HIVE/HBD price feed\n\n * `bias` - if HBD is trading at only 0.90 USD on exchanges, the witness might set:\n        base: 0.250 HBD\n        quote: 1.100 HIVE\n      In this case, the bias is 10%\n\n * `feed_age` - how old their feed value is\n\n * `block_size` - the block size they're voting for\n\n * `signing_key` - the witness' block-signing public key\n\n * `version` - the version of hived the witness is running\n"
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
                    "witness": "arcange",
                    "rank": 1,
                    "url": "https://peakd.com/witness-category/@arcange/witness-update-202103",
                    "vests": 141591182132060780,
                    "votes_hive_power": 81865807173,
                    "votes_daily_change": 39841911089,
                    "votes_daily_change_hive_power": 23036,
                    "voters_num": 4481,
                    "voters_num_daily_change": 5,
                    "price_feed": 0.302,
                    "bias": 0,
                    "feed_age": "00:45:20.244402",
                    "block_size": 65536,
                    "signing_key": "STM6wjYfYn728hR5yXNBS5GcMoACfYymKEWW1WFzDGiMaeo9qUKwH",
                    "version": "1.27.4",
                    "missed_blocks": 697,
                    "hbd_interest_rate": 2000
                  },
                  {
                    "witness": "gtg",
                    "rank": 2,
                    "url": "https://gtg.openhive.network",
                    "vests": 141435014237847520,
                    "votes_hive_power": 81775513339,
                    "votes_daily_change": 186512763933,
                    "votes_daily_change_hive_power": 107839,
                    "voters_num": 3131,
                    "voters_num_daily_change": 4,
                    "price_feed": 0.3,
                    "bias": 0,
                    "feed_age": "00:55:26.244402",
                    "block_size": 65536,
                    "signing_key": "STM5dLh5HxjjawY4Gm6o6ugmJUmEXgnfXXXRJPRTxRnvfFBJ24c1M",
                    "version": "1.27.5",
                    "missed_blocks": 986,
                    "hbd_interest_rate": 1500
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
        "description": "Return a single witness given their account name\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_witness('gtg');`\n\n* `SELECT * FROM hafbe_endpoints.get_witness('blocktrades');`\n\nREST call example\n* `GET https://{hafbe-host}/hafbe/witnesses/gtg`\n\n* `GET https://{hafbe-host}/hafbe/witnesses/blocktrades`\n",
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
                  "witness": "arcange",
                  "rank": 1,
                  "url": "https://peakd.com/witness-category/@arcange/witness-update-202103",
                  "vests": 141591182132060780,
                  "votes_hive_power": 81865807173,
                  "votes_daily_change": 39841911089,
                  "votes_daily_change_hive_power": 23036,
                  "voters_num": 4481,
                  "voters_num_daily_change": 5,
                  "price_feed": 0.302,
                  "bias": 0,
                  "feed_age": "00:45:20.244402",
                  "block_size": 65536,
                  "signing_key": "STM6wjYfYn728hR5yXNBS5GcMoACfYymKEWW1WFzDGiMaeo9qUKwH",
                  "version": "1.27.4",
                  "missed_blocks": 697,
                  "hbd_interest_rate": 2000
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
        "description": "Get information about the voters voting for a given witness\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_witness_voters('gtg');`\n\n* `SELECT * FROM hafbe_endpoints.get_witness_voters('blocktrades');`\n\nREST call example\n* `GET https://{hafbe-host}/hafbe/witnesses/gtg/voters`\n\n* `GET https://{hafbe-host}/hafbe/witnesses/blocktrades/voters`\n",
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
            "description": "Sort order:\n\n * `voter` - total number of voters casting their votes for each witness.  this probably makes no sense for call???\n\n * `vests` - total weight of vests casting their votes for each witness\n\n * `account_vests` - total weight of vests owned by accounts voting for each witness\n\n * `proxied_vests` - total weight of vests owned by accounts who proxy their votes to a voter voting for each witness\n\n * `timestamp` - the time the voter last changed their vote???\n"
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
                    "voter": "reugie",
                    "vests": 1492852870616,
                    "vests_hive_power": 863149,
                    "account_vests": 1492852870616,
                    "account_hive_power": 863149,
                    "proxied_vests": 0,
                    "proxied_hive_power": 0,
                    "timestamp": "2024-03-27T14:46:09.000Z"
                  },
                  {
                    "voter": "cooperclub",
                    "vests": 8238935864379,
                    "vests_hive_power": 4763650,
                    "account_vests": 8238935864379,
                    "account_hive_power": 4763650,
                    "proxied_vests": 0,
                    "proxied_hive_power": 0,
                    "timestamp": "2024-03-27T14:42:06.000Z"
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
        "description": "Get the number of voters for a witness given their account name\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_witness_voters_num('gtg');`\n\n* `SELECT * FROM hafbe_endpoints.get_witness_voters_num('blocktrades');`\n\nREST call example\n* `GET https://{hafbe-host}/hafbe/witnesses/gtg/voters/count`\n\n* `GET https://{hafbe-host}/hafbe/witnesses/blocktrades/voters/count`\n",
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
                "example": 3131
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
        "description": "Get information about each vote cast for this witness\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_witness_votes_history('gtg');`\n\n* `SELECT * FROM hafbe_endpoints.get_witness_votes_history('blocktrades');`\n\nREST call example\n* `GET https://{hafbe-host}/hafbe/witnesses/gtg/votes/history`\n\n* `GET https://{hafbe-host}/hafbe/witnesses/blocktrades/votes/history`\n",
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
            "description": "Sort order:\n\n * `voter` - total number of voters casting their votes for each witness.  this probably makes no sense for this call???\n\n * `vests` - total weight of vests casting their votes for each witness\n\n * `account_vests` - total weight of vests owned by accounts voting for each witness\n\n * `proxied_vests` - total weight of vests owned by accounts who proxy their votes to a voter voting for each witness\n\n * `timestamp` - the time the voter last changed their vote???\n"
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
              "x-sql-default-value": "'1970-01-01T00:00:00'::TIMESTAMP"
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
                    "voter": "reugie",
                    "approve": true,
                    "vests": 1492852870616,
                    "vests_hive_power": 863149,
                    "account_vests": 1492852870616,
                    "account_hive_power": 863149,
                    "proxied_vests": 0,
                    "proxied_hive_power": 0,
                    "timestamp": "2024-03-27T14:46:09.000Z"
                  },
                  {
                    "voter": "cooperclub",
                    "approve": true,
                    "vests": 8238935864379,
                    "vests_hive_power": 4763650,
                    "account_vests": 8238935864379,
                    "account_hive_power": 4763650,
                    "proxied_vests": 0,
                    "proxied_hive_power": 0,
                    "timestamp": "2024-03-27T14:42:06.000Z"
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
        "description": "Get information about account's balances and parameters\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_account('blocktrades');`\n\n* `SELECT * FROM hafbe_endpoints.get_account('initminer');`\n\nREST call example\n* `GET https://{hafbe-host}/hafbe/accounts/blocktrades`\n\n* `GET https://{hafbe-host}/hafbe/accounts/initminer`\n",
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
            "description": "The account's parameters\n\n* Returns `hafbe_types.account`\n",
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
                    "proxy": null,
                    "recovery_account": "steem",
                    "last_account_recovery": "1970-01-01T00:00:00",
                    "created": "2016-03-30T00:04:33",
                    "reputation": "79,",
                    "json_metadata": "",
                    "posting_json_metadata": "",
                    "profile_image": "",
                    "hbd_balance": 19137472,
                    "balance": 352144597,
                    "vesting_shares": 20689331636290595,
                    "vesting_balance": 11996826266,
                    "hbd_saving_balance": 108376848,
                    "savings_balance": 52795,
                    "savings_withdraw_requests": 0,
                    "reward_hbd_balance": 0,
                    "reward_hive_balance": 0,
                    "reward_vesting_balance": 0,
                    "reward_vesting_hive": 0,
                    "posting_rewards": 124692738,
                    "curation_rewards": 2778463006,
                    "delegated_vesting_shares": 7002130390740040,
                    "received_vesting_shares": 93226683463768,
                    "proxied_vsf_votes": "[19944304439583785, 0, 0, 0]",
                    "withdrawn": 0,
                    "vesting_withdraw_rate": 0,
                    "to_withdraw": 0,
                    "withdraw_routes": 3,
                    "delayed_vests": 0,
                    "witness_votes": "[\"blocktrades\", \"pharesim\", \"abit\"]",
                    "witnesses_voted_for": 3,
                    "ops_count": 6558823,
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
        "description": "Get information about account's OWNER, ACTIVE, POSTING, memo and signing authorities\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_account_authority('blocktrades');`\n\n* `SELECT * FROM hafbe_endpoints.get_account_authority('initminer');`\n\nREST call example\n* `GET https://{hafbe-host}/hafbe/accounts/blocktrades/authority`\n\n* `GET https://{hafbe-host}/hafbe/accounts/initminer/authority`\n",
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
            "description": "List of account's authorities\n\n* Returns `hafbe_types.account_authority`\n",
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
                          "STM7sw22HqsXbz7D2CmJfmMwt9rimtk518dRzsR1f8Cgw52dQR1pR",
                          "1"
                        ]
                      ],
                      "account_auth": [],
                      "weight_threshold": 1
                    },
                    "active": {
                      "key_auth": [
                        [
                          "STM7sw22HqsXbz7D2CmJfmMwt9rimtk518dRzsR1f8Cgw52dQR1pR",
                          "1"
                        ]
                      ],
                      "account_auth": [],
                      "weight_threshold": 1
                    },
                    "posting": {
                      "key_auth": [
                        [
                          "STM7sw22HqsXbz7D2CmJfmMwt9rimtk518dRzsR1f8Cgw52dQR1pR",
                          "1"
                        ]
                      ],
                      "account_auth": [],
                      "weight_threshold": 1
                    },
                    "memo": "STM78Vaf41p9UUMMJvafLTjMurnnnuAiTqChiT5GBph7VDWahQRsz",
                    "witness_signing": "STM776t8h7dXbvM8BYGoLjCr3nYRnmqmvVg9hTrGTn5FQvLkMZKM2"
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
    "/accounts/{account-name}/operations": {
      "get": {
        "tags": [
          "Accounts"
        ],
        "summary": "Get operations for an account",
        "description": "List the operations in the reversed  order (first page is the oldest) for given account. \nThe page size determines the number of operations per page\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_ops_by_account('blocktrades');`\n\n* `SELECT * FROM hafbe_endpoints.get_ops_by_account('gtg');`\n\nREST call example\n* `GET https://{hafbe-host}/hafbe/accounts/blocktrades/operations`\n\n* `GET https://{hafbe-host}/hafbe/accounts/gtg/operations`\n",
        "operationId": "hafbe_endpoints.get_ops_by_account",
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
            "description": "List of operations: if the parameter is empty, all operations will be included\nsql example: `'18,12'`\n"
          },
          {
            "in": "query",
            "name": "page",
            "required": false,
            "schema": {
              "type": "integer",
              "default": null
            },
            "description": "Return page on `page` number, default null due to reversed order of pages\nthe first page is the oldest\n"
          },
          {
            "in": "query",
            "name": "page-size",
            "required": false,
            "schema": {
              "type": "integer",
              "default": 100
            },
            "description": "Return max `page-size` operations per page"
          },
          {
            "in": "query",
            "name": "data-size-limit",
            "required": false,
            "schema": {
              "type": "integer",
              "default": 200000
            },
            "description": "If the operation length exceeds the data size limit,\nthe operation body is replaced with a placeholder\n"
          },
          {
            "in": "query",
            "name": "from-block",
            "required": false,
            "schema": {
              "type": "integer",
              "default": null
            },
            "description": "Lower limit of the block range"
          },
          {
            "in": "query",
            "name": "to-block",
            "required": false,
            "schema": {
              "type": "integer",
              "default": null
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
                    "total_operations": 4417,
                    "total_pages": 45,
                    "operations_result": [
                      {
                        "operation_id": 21474759170589000,
                        "block_num": 4999982,
                        "trx_in_block": 0,
                        "trx_id": "fa7c8ac738b4c1fdafd4e20ee6ca6e431b641de3",
                        "op_pos": 1,
                        "op_type_id": 72,
                        "operation": {
                          "type": "effective_comment_vote_operation",
                          "value": {
                            "voter": "gtg",
                            "author": "skypilot",
                            "weight": "19804864940707296",
                            "rshares": 87895502383,
                            "permlink": "sunset-at-point-sur-california",
                            "pending_payout": {
                              "nai": "@@000000013",
                              "amount": "14120",
                              "precision": 3
                            },
                            "total_vote_weight": "14379148533547713492"
                          }
                        },
                        "virtual_op": true,
                        "timestamp": "2016-09-15T19:46:21",
                        "age": "2820 days 02:03:05.095628",
                        "is_modified": false
                      },
                      {
                        "operation_id": 21474759170588670,
                        "block_num": 4999982,
                        "trx_in_block": 0,
                        "trx_id": "fa7c8ac738b4c1fdafd4e20ee6ca6e431b641de3",
                        "op_pos": 0,
                        "op_type_id": 0,
                        "operation": {
                          "type": "vote_operation",
                          "value": {
                            "voter": "gtg",
                            "author": "skypilot",
                            "weight": 10000,
                            "permlink": "sunset-at-point-sur-california"
                          }
                        },
                        "virtual_op": false,
                        "timestamp": "2016-09-15T19:46:21",
                        "age": "2820 days 02:03:05.095628",
                        "is_modified": false
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
    "/accounts/{account-name}/operations/types": {
      "get": {
        "tags": [
          "Accounts"
        ],
        "summary": "Lists operation types",
        "description": "Lists all types of operations that the account has performed since its creation\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_acc_op_types('blocktrades');`\n\n* `SELECT * FROM hafbe_endpoints.get_acc_op_types('initminer');`\n\nREST call example\n* `GET https://{hafbe-host}/hafbe/accounts/blocktrades/operations/types`\n\n* `GET https://{hafbe-host}/hafbe/accounts/initminer/operations/types`\n",
        "operationId": "hafbe_endpoints.get_acc_op_types",
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
            "description": "Operation type list\n\n* Returns array of `hafbe_types.op_types`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hafbe_types.array_of_op_types"
                },
                "example": [
                  {
                    "op_type_id": 72,
                    "operation_name": "effective_comment_vote_operation",
                    "is_virtual": true
                  },
                  {
                    "op_type_id": 0,
                    "operation_name": "vote_operation",
                    "is_virtual": false
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
    "/accounts/{account-name}/operations/comments": {
      "get": {
        "tags": [
          "Accounts"
        ],
        "summary": "Get comment related operations",
        "description": "List operations related to account and optionally filtered by permlink,\ntime/blockrange and comment related operations\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_comment_operations('blocktrades');`\n\n* `SELECT * FROM hafbe_endpoints.get_comment_operations('gtg');`\n\nREST call example\n* `GET https://{hafbe-host}/hafbe/accounts/blocktrades/operations/comments`\n\n* `GET https://{hafbe-host}/hafbe/accounts/gtg/operations/comments`\n",
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
              "x-sql-default-value": "'0, 1, 17, 19, 51, 52, 53, 61, 63, 72, 73'"
            },
            "description": "List of operations: if the parameter is NULL, all operations will be included\nsql example: `'18,12'`\n"
          },
          {
            "in": "query",
            "name": "page",
            "required": false,
            "schema": {
              "type": "integer",
              "default": 1
            },
            "description": "Return page on `page` number"
          },
          {
            "in": "query",
            "name": "permlink",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Unique post identifier containing post's title and generated number\n"
          },
          {
            "in": "query",
            "name": "page-size",
            "required": false,
            "schema": {
              "type": "integer",
              "default": 100
            },
            "description": "Return max `page-size` operations per page"
          },
          {
            "in": "query",
            "name": "data-size-limit",
            "required": false,
            "schema": {
              "type": "integer",
              "default": 200000
            },
            "description": "If the operation length exceeds the `data-size-limit`,\nthe operation body is replaced with a placeholder\n"
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
                    "total_operations": 1,
                    "total_pages": 1,
                    "operations_result": [
                      {
                        "operation_id": 5287104741440,
                        "block_num": 1231,
                        "trx_in_block": -1,
                        "trx_id": null,
                        "op_pos": 1,
                        "op_type_id": 64,
                        "operation": {
                          "type": "producer_reward_operation",
                          "value": {
                            "producer": "root",
                            "vesting_shares": {
                              "nai": "@@000000021",
                              "amount": "1000",
                              "precision": 3
                            }
                          }
                        },
                        "virtual_op": true,
                        "timestamp": "2016-03-24T17:07:15",
                        "age": "2993 days 16:17:51.591008",
                        "is_modified": false
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
    "/blocks": {
      "get": {
        "tags": [
          "Blocks"
        ],
        "summary": "Informations about number of operations in block",
        "description": "Lists counts of operations in last `result-limit` blocks and its creator\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_latest_blocks();`\n\n* `SELECT * FROM hafbe_endpoints.get_latest_blocks(20);`\n\nREST call example\n* `GET https://{hafbe-host}/hafbe/blocks`\n\n* `GET https://{hafbe-host}/hafbe/blocks?result-limit=20`\n",
        "operationId": "hafbe_endpoints.get_latest_blocks",
        "parameters": [
          {
            "in": "query",
            "name": "result-limit",
            "required": false,
            "schema": {
              "type": "integer",
              "default": 20
            },
            "description": "Return max `result-limit` operations per page"
          }
        ],
        "responses": {
          "200": {
            "description": "Given block's stats\n\n* Returns array of `hafbe_types.latest_blocks`\n",
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
                        "op_type_id": 0
                      },
                      {
                        "count": 2,
                        "op_type_id": 85
                      },
                      {
                        "count": 1,
                        "op_type_id": 30
                      }
                    ]
                  },
                  {
                    "block_num": 4999999,
                    "witness": "smooth.witness",
                    "ops_count": [
                      {
                        "count": 1,
                        "op_type_id": 0
                      },
                      {
                        "count": 2,
                        "op_type_id": 85
                      },
                      {
                        "count": 1,
                        "op_type_id": 30
                      },
                      {
                        "count": 2,
                        "op_type_id": 6
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
    "/blocks/{block-num}": {
      "get": {
        "tags": [
          "Blocks"
        ],
        "summary": "Informations about block",
        "description": "Lists the parameters of the block provided by the user\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_block(10000);`\n\n* `SELECT * FROM hafbe_endpoints.get_block(43000);`\n\nREST call example\n* `GET https://{hafbe-host}/hafbe/blocks/10000`\n\n* `GET https://{hafbe-host}/hafbe/blocks/43000`\n",
        "operationId": "hafbe_endpoints.get_block",
        "parameters": [
          {
            "in": "path",
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
            "description": "Given block's stats\n\n* Returns `hafbe_types.block`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hafbe_types.block"
                },
                "example": [
                  {
                    "block_num": 1231,
                    "hash": "\\\\x000004cf8319149b0743acdcf2a17a332677fb0f",
                    "prev": "\\\\x000004ce0536f08f1e09c3dc7b12b8ddf13f1c5a",
                    "producer_account": "producer_account",
                    "transaction_merkle_root": "\\\\x0000000000000000000000000000000000000000",
                    "extensions": null,
                    "witness_signature": "\\\\x207f255f2d6c69c04ccfa4a541792a773412307735ccf96ba9e12d9c84b714c4711cf1d1bed561994c46daf33a24e8071f15f92",
                    "signing_key": "STM65wH1LZ7BfSHcK69SShnqCAH5xdoSZpGkUjmzHJ5GCuxEK9V5G",
                    "hbd_interest_rate": 1000,
                    "total_vesting_fund_hive": 28000,
                    "total_vesting_shares": 28000000,
                    "total_reward_fund_hive": 2462000,
                    "virtual_supply": 4932000,
                    "current_supply": 4932000,
                    "current_hbd_supply": 0,
                    "dhf_interval_ledger": 0,
                    "created_at": "2016-03-24T17:07:15",
                    "age": "2993 days 15:24:08.630023"
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
    "/blocks/{block-num}/raw-details": {
      "get": {
        "tags": [
          "Blocks"
        ],
        "summary": "Raw informations about block",
        "description": "Lists the raw parameters of the block provided by the user\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_block_raw(10000);`\n\n* `SELECT * FROM hafbe_endpoints.get_block_raw(43000);`\n\nREST call example\n* `GET https://{hafbe-host}/hafbe/blocks/10000/raw-details`\n\n* `GET https://{hafbe-host}/hafbe/blocks/43000/raw-details`\n",
        "operationId": "hafbe_endpoints.get_block_raw",
        "parameters": [
          {
            "in": "path",
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
            "description": "Given block's raw stats\n\n* Returns `hafbe_types.block_raw`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hafbe_types.block_raw"
                },
                "example": [
                  {
                    "previous": "\\\\x000004ce0536f08f1e09c3dc7b12b8ddf13f1c5a",
                    "timestamp": "2016-03-24T17:07:15",
                    "witness": "root",
                    "transaction_merkle_root": "\\\\x0000000000000000000000000000000000000000",
                    "extensions": [],
                    "witness_signature": "\\\\x207f255f2d6c69c04ccfa4a541792a773412307735ccf90bd8efb26ba9e12d9c84b714c4711cf1d1bed561994c46daf33a24e8071f15f92",
                    "transactions": [],
                    "block_id": "\\\\x000004cf8319149b0743acdcf2a17a332677fb0f",
                    "signing_key": "STM65wH1LZ7BfSHcK69SShnqCAH5xdoSZpGkUjmzHJ5GCuxEK9V5G",
                    "transaction_ids": null
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
    "/blocks/{block-num}/operations": {
      "get": {
        "tags": [
          "Blocks"
        ],
        "summary": "Get operations in block",
        "description": "List the operations in the specified order that are within the given block number. \nThe page size determines the number of operations per page\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_ops_by_block_paging(10000);`\n\n* `SELECT * FROM hafbe_endpoints.get_ops_by_block_paging(43000,ARRAY[0,1]);`\n\nREST call example\n* `GET https://{hafbe-host}/hafbe/blocks/10000/operations`\n\n* `GET https://{hafbe-host}/hafbe/blocks/43000/operations?operation-types=0,1`\n",
        "operationId": "hafbe_endpoints.get_ops_by_block_paging",
        "parameters": [
          {
            "in": "path",
            "name": "block-num",
            "required": true,
            "schema": {
              "type": "integer"
            },
            "description": "List operations from given block number"
          },
          {
            "in": "query",
            "name": "operation-types",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "List of operations: if the parameter is empty, all operations will be included\nsql example: `'18,12'`\n"
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
            "name": "page",
            "required": false,
            "schema": {
              "type": "integer",
              "default": 1
            },
            "description": "Return page on `page` number"
          },
          {
            "in": "query",
            "name": "page-size",
            "required": false,
            "schema": {
              "type": "integer",
              "default": 100
            },
            "description": "Return max `page-size` operations per page"
          },
          {
            "in": "query",
            "name": "set-of-keys",
            "required": false,
            "schema": {
              "type": "string",
              "x-sql-datatype": "JSON",
              "default": null
            },
            "description": "A JSON object detailing the path to the filtered key specified in key-content\nsql example: `[[\"value\", \"id\"]]`\n"
          },
          {
            "in": "query",
            "name": "key-content",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "A parameter specifying the desired value related to the set-of-keys\nsql example: `'follow'`\n"
          },
          {
            "in": "query",
            "name": "direction",
            "required": false,
            "schema": {
              "$ref": "#/components/schemas/hafbe_types.sort_direction",
              "default": "desc"
            },
            "description": "Sort order:\n\n * `asc` - Ascending, from A to Z or smallest to largest\n \n * `desc` - Descending, from Z to A or largest to smallest\n"
          },
          {
            "in": "query",
            "name": "data-size-limit",
            "required": false,
            "schema": {
              "type": "integer",
              "default": 200000
            },
            "description": "If the operation length exceeds the data size limit,\nthe operation body is replaced with a placeholder\n"
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
                    "total_operations": 1,
                    "total_pages": 1,
                    "operations_result": [
                      {
                        "operation_id": 5287104741440,
                        "block_num": 1231,
                        "trx_in_block": -1,
                        "trx_id": null,
                        "op_pos": 1,
                        "op_type_id": 64,
                        "operation": {
                          "type": "producer_reward_operation",
                          "value": {
                            "producer": "root",
                            "vesting_shares": {
                              "nai": "@@000000021",
                              "amount": "1000",
                              "precision": 3
                            }
                          }
                        },
                        "virtual_op": true,
                        "timestamp": "2016-03-24T17:07:15",
                        "age": "2993 days 16:17:51.591008",
                        "is_modified": false
                      }
                    ]
                  }
                ]
              }
            }
          },
          "404": {
            "description": "The result is empty"
          }
        }
      }
    },
    "/blocks/{block-num}/operations/count": {
      "get": {
        "tags": [
          "Blocks"
        ],
        "summary": "Count operations in block",
        "description": "List count for each operation type for given block number\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_op_count_in_block(10000);`\n\n* `SELECT * FROM hafbe_endpoints.get_op_count_in_block(43000);`\n\nREST call example\n* `GET https://{hafbe-host}/hafbe/blocks/10000/operations/count`\n\n* `GET https://{hafbe-host}/hafbe/blocks/43000/operations/count`\n",
        "operationId": "hafbe_endpoints.get_op_count_in_block",
        "parameters": [
          {
            "in": "path",
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
            "description": "Given block's operations count\n\n* Returns array of `hafbe_types.op_count_in_block`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hafbe_types.array_of_op_count_in_block"
                },
                "example": [
                  {
                    "op_type_id": 0,
                    "count": 1
                  },
                  {
                    "op_type_id": 1,
                    "count": 5
                  },
                  {
                    "op_type_id": 72,
                    "count": 1
                  }
                ]
              }
            }
          },
          "404": {
            "description": "No block in the database"
          }
        }
      }
    },
    "/blocks/{block-num}/operations/types": {
      "get": {
        "tags": [
          "Blocks"
        ],
        "summary": "List operations that were present in given block",
        "description": "List operations that were present in given block\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_block_op_types(10000);`\n\n* `SELECT * FROM hafbe_endpoints.get_block_op_types(43000);`\n\nREST call example\n* `GET https://{hafbe-host}/hafbe/blocks/10000/operations/types`\n\n* `GET https://{hafbe-host}/hafbe/blocks/43000/operations/types`\n",
        "operationId": "hafbe_endpoints.get_block_op_types",
        "parameters": [
          {
            "in": "path",
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
            "description": "Given block's operation list\n\n* Returns array of `hafbe_types.op_types`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hafbe_types.array_of_op_types"
                },
                "example": [
                  {
                    "op_type_id": 72,
                    "operation_name": "effective_comment_vote_operation",
                    "is_virtual": true
                  },
                  {
                    "op_type_id": 0,
                    "operation_name": "vote_operation",
                    "is_virtual": false
                  }
                ]
              }
            }
          },
          "404": {
            "description": "No block in the database"
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
        "description": "List the block numbers that match given operation type filter,\naccount name and time/block range in specified order\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_block_by_op(ARRAY[14]);`\n\n* `SELECT * FROM hafbe_endpoints.get_block_by_op();`\n\nREST call example\n* `GET https://{hafbe-host}/hafbe/block-numbers?operation-types={14}`\n\n* `GET https://{hafbe-host}/hafbe/block-numbers`\n",
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
            "description": "List of operations: if the parameter is NULL, all operations will be included\nsql example: `'18,12'`\n"
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
            "name": "set-of-keys",
            "required": false,
            "schema": {
              "type": "string",
              "x-sql-datatype": "JSON",
              "default": null
            },
            "description": "A JSON object detailing the path to the filtered key specified in key-content\nsql example: `[[\"value\", \"id\"]]`\n"
          },
          {
            "in": "query",
            "name": "key-content",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "A parameter specifying the desired value related to the set-of-keys\nsql example: `'follow'`\n"
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
                    "block_num": 5000000,
                    "op_type_id": [
                      9,
                      5,
                      64,
                      80
                    ]
                  },
                  {
                    "block_num": 4999999,
                    "op_type_id": [
                      64,
                      30,
                      6,
                      0,
                      85,
                      72,
                      78
                    ]
                  },
                  {
                    "block_num": 4999998,
                    "op_type_id": [
                      1,
                      64,
                      0,
                      72
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
        "description": "Get last block-num in HAF database\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_head_block_num();`\n\nREST call example\n* `GET https://{hafbe-host}/hafbe/block-numbers/headblock`\n",
        "operationId": "hafbe_endpoints.get_head_block_num",
        "responses": {
          "200": {
            "description": "Last HAF block\n\n* Returns `INT`\n",
            "content": {
              "application/json": {
                "schema": {
                  "type": "integer"
                },
                "example": 3131
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
        "summary": "Haf_block_explorer's last synced block",
        "description": "Get last block-num synced by haf_block_explorer\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_hafbe_last_synced_block();`\n\nREST call example\n* `GET https://{hafbe-host}/hafbe/block-numbers/headblock/hafbe`\n",
        "operationId": "hafbe_endpoints.get_hafbe_last_synced_block",
        "responses": {
          "200": {
            "description": "Last synced block\n\n* Returns `INT`\n",
            "content": {
              "application/json": {
                "schema": {
                  "type": "integer"
                },
                "example": 3131
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
        "description": "Returns last created block number for given date\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_block_by_time('2016-03-24T16:05:00');`\n\nREST call example\n* `GET https://{hafbe-host}/hafbe/block-numbers/by-creation-date/2016-03-24T16:05:00`\n",
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
                "example": 3131
              }
            }
          }
        }
      }
    },
    "/operations/types": {
      "get": {
        "tags": [
          "Operations"
        ],
        "summary": "Lists operation types",
        "description": "Lists all types of operations available in the database\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_op_types();`\n\n* `SELECT * FROM hafbe_endpoints.get_op_types('comment');`\n\nREST call example\n* `GET https://{hafbe-host}/hafbe/operation-types`\n\n* `GET https://{hafbe-host}/hafbe/operation-types?input-value=\"comment\"`\n",
        "operationId": "hafbe_endpoints.get_op_types",
        "parameters": [
          {
            "in": "query",
            "name": "input-value",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "parial name of operation"
          }
        ],
        "responses": {
          "200": {
            "description": "Operation type list, \nif provided is `input-value` the list\nis limited to operations that partially match the `input-value`\n\n* Returns array of `hafbe_types.op_types`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hafbe_types.array_of_op_types"
                },
                "example": [
                  {
                    "op_type_id": 72,
                    "operation_name": "effective_comment_vote_operation",
                    "is_virtual": true
                  },
                  {
                    "op_type_id": 0,
                    "operation_name": "vote_operation",
                    "is_virtual": false
                  }
                ]
              }
            }
          },
          "404": {
            "description": "No operations in the database"
          }
        }
      }
    },
    "/operations/types/{type-id}/keys": {
      "get": {
        "tags": [
          "Operations"
        ],
        "summary": "Get operation json body keys",
        "description": "Lists possible json key paths in operation body for given operation type id\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_operation_keys(1);`\n\nREST call example\n* `GET https://{hafbe-host}/hafbe//operations/types/1/keys`\n",
        "operationId": "hafbe_endpoints.get_operation_keys",
        "parameters": [
          {
            "in": "path",
            "name": "type-id",
            "required": true,
            "schema": {
              "type": "integer"
            },
            "description": "Unique operation identifier"
          }
        ],
        "responses": {
          "200": {
            "description": "Operation json key paths\n\n* Returns array of `TEXT[]`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hafbe_types.array_of_text_array"
                },
                "example": [
                  [
                    "value",
                    "body"
                  ],
                  [
                    "value",
                    "title"
                  ],
                  [
                    "value",
                    "author"
                  ],
                  [
                    "value",
                    "permlink"
                  ],
                  [
                    "value",
                    "json_metadata"
                  ],
                  [
                    "value",
                    "parent_author"
                  ],
                  [
                    "value",
                    "parent_permlink"
                  ]
                ]
              }
            }
          },
          "404": {
            "description": "No such operation"
          }
        }
      }
    },
    "/operations/body/{operation-id}": {
      "get": {
        "tags": [
          "Operations"
        ],
        "summary": "Get informations about the operation",
        "description": "Get operation's body and its extended parameters\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_operation(3448858738752);`\n\nREST call example\n* `GET https://{hafbe-host}/hafbe/operations/3448858738752`\n",
        "operationId": "hafbe_endpoints.get_operation",
        "parameters": [
          {
            "in": "path",
            "name": "operation-id",
            "required": true,
            "schema": {
              "type": "integer",
              "x-sql-datatype": "BIGINT"
            },
            "description": "Unique operation identifier"
          }
        ],
        "responses": {
          "200": {
            "description": "Operation parameters\n\n* Returns `hafbe_types.operation`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hafbe_types.operation"
                },
                "example": [
                  {
                    "operation_id": 4294967376,
                    "block_num": 1,
                    "trx_in_block": -1,
                    "trx_id": null,
                    "op_pos": 1,
                    "op_type_id": 80,
                    "operation": {
                      "type": "account_created_operation",
                      "value": {
                        "creator": "miners",
                        "new_account_name": "miners",
                        "initial_delegation": {
                          "nai": "@@000000037",
                          "amount": "0",
                          "precision": 6
                        },
                        "initial_vesting_shares": {
                          "nai": "@@000000037",
                          "amount": "0",
                          "precision": 6
                        }
                      }
                    },
                    "virtual_op": true,
                    "timestamp": "2016-03-24T16:00:00",
                    "ag\"": "2995 days 00:02:08.146978",
                    "is_modified": false
                  }
                ]
              }
            }
          },
          "404": {
            "description": "No such operation"
          }
        }
      }
    },
    "/transactions/{transaction-id}": {
      "get": {
        "tags": [
          "Transactions"
        ],
        "summary": "Get transaction info",
        "description": "Get information about transaction \n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_transaction('954f6de36e6715d128fa8eb5a053fc254b05ded0');`\n\nREST call example\n* `GET https://{hafbe-host}/hafbe/transactions/954f6de36e6715d128fa8eb5a053fc254b05ded0`\n",
        "operationId": "hafbe_endpoints.get_transaction",
        "parameters": [
          {
            "in": "path",
            "name": "transaction-id",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "The transaction hash"
          }
        ],
        "responses": {
          "200": {
            "description": "The transaction body\n\n* Returns `hafbe_types.transaction`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hafbe_types.transaction"
                },
                "example": [
                  {
                    "transaction_json": {
                      "ref_block_num": 25532,
                      "ref_block_prefix": 3338687976,
                      "extensions": [],
                      "expiration": "2016-08-12T17:23:48",
                      "operations": [
                        {
                          "type": "custom_json_operation",
                          "value": {
                            "id": "follow",
                            "json": "{\"follower\":\"breck0882\",\"following\":\"steemship\",\"what\":[]}",
                            "required_auths": [],
                            "required_posting_auths": [
                              "breck0882"
                            ]
                          }
                        }
                      ],
                      "signatures": [
                        "201655190aac43bb272185c577262796c57e5dd654e3e491b921a38697d04d1a8e6a9deb722ec6d6b5d2f395dcfbb94f0e5898e858f"
                      ]
                    },
                    "transaction_id": "954f6de36e6715d128fa8eb5a053fc254b05ded0",
                    "block_num": 4023233,
                    "transaction_num": 0,
                    "timestamp": "2016-08-12T17:23:39",
                    "age": "2852 days 15:46:22.097754"
                  }
                ]
              }
            }
          },
          "404": {
            "description": "No such transaction"
          }
        }
      }
    },
    "/version": {
      "get": {
        "tags": [
          "Other"
        ],
        "summary": "Haf_block_explorer's version",
        "description": "Get haf_block_explorer's last commit hash that determinates its version\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_hafbe_version();`\n\nREST call example\n* `GET https://{hafbe-host}/hafbe/version`\n",
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
        "description": "Determines whether the entered value is a block,\nblock hash, transaction hash, or account name\n\nSQL example\n* `SELECT * FROM hafbe_endpoints.get_input_type('blocktrades');`\n\n* `SELECT * FROM hafbe_endpoints.get_input_type('10000');`\n\nREST call example\n* `GET https://{hafbe-host}/hafbe/input-type/blocktrades`\n\n* `GET https://{hafbe-host}/hafbe/input-type/10000`\n",
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
                    "input_type": "block_num",
                    "input_value": "1000"
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
    }
  }
}
$$;
-- openapi-generated-code-end
begin
  return openapi;
end
$_$ language plpgsql;

RESET ROLE;
