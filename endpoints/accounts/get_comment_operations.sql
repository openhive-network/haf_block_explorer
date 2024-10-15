SET ROLE hafbe_owner;

/** openapi:paths
/accounts/{account-name}/comment-operations:
  get:
    tags:
      - Accounts
    summary: Get comment-related operations for an account.
    description: |
      List operations related to account. Optionally filtered by permlink,
      time/blockrange, and specific comment-related operations.

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_comment_operations(''blocktrades'');`
      
      REST call example
      * `GET ''https://%1$s/hafbe-api/accounts/blocktrades/comment-operations?page-size=2&from-block=4000000&to-block=5000000''`
    operationId: hafbe_endpoints.get_comment_operations
    parameters:
      - in: path
        name: account-name
        required: true
        schema:
          type: string
        description: Account to get operations for
      - in: query
        name: operation-types
        required: false
        schema:
          type: string
          default: NULL
        description: |
          List of operation types to include. If NULL, all comment operation types will be included.
          comment-related operation type ids: `0, 1, 17, 19, 51, 52, 53, 61, 63, 72, 73`
      - in: query
        name: page
        required: false
        schema:
          type: integer
          default: 1
        description: Return page on `page` number, defaults to `1`
      - in: query
        name: permlink
        required: false
        schema:
          type: string
          default: NULL
        description: |
            Unique post identifier containing post''s title and generated number
      - in: query
        name: page-size
        required: false
        schema:
          type: integer
          default: 100
        description: Return max `page-size` operations per page, defaults to `100`
      - in: query
        name: data-size-limit
        required: false
        schema:
          type: integer
          default: 200000
        description: |
          If the operation length exceeds the `data-size-limit`,
          the operation body is replaced with a placeholder (defaults to `200000`).
      - in: query
        name: from-block
        required: false
        schema:
          type: string
          default: NULL
        description: |
          Lower limit of the block range, can be represented either by a block-number (integer) or a timestamp (in the format YYYY-MM-DD HH:MI:SS).

          The provided `timestamp` will be converted to a `block-num` by finding the first block 
          where the block''s `created_at` is more than or equal to the given `timestamp` (i.e. `block''s created_at >= timestamp`).

          The function will interpret and convert the input based on its format, example input:

          * `2016-09-15 19:47:21`

          * `5000000`
      - in: query
        name: to-block
        required: false
        schema:
          type: string
          default: NULL
        description: | 
          Similar to the from-block parameter, can either be a block-number (integer) or a timestamp (formatted as YYYY-MM-DD HH:MI:SS). 

          The provided `timestamp` will be converted to a `block-num` by finding the first block 
          where the block''s `created_at` is less than or equal to the given `timestamp` (i.e. `block''s created_at <= timestamp`).
          
          The function will convert the value depending on its format, example input:

          * `2016-09-15 19:47:21`

          * `5000000`
    responses:
      '200':
        description: |
          Result contains total number of operations,
          total pages, and the list of operations.

          * Returns `JSON`
        content:
          application/json:
            schema:
              type: string
              x-sql-datatype: JSON
            example:  
              - {
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
      '404':
        description: No such account in the database
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_comment_operations;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_comment_operations(
    "account-name" TEXT,
    "operation-types" TEXT = NULL,
    "page" INT = 1,
    "permlink" TEXT = NULL,
    "page-size" INT = 100,
    "data-size-limit" INT = 200000,
    "from-block" TEXT = NULL,
    "to-block" TEXT = NULL
)
RETURNS JSON 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
SET join_collapse_limit = 16
SET from_collapse_limit = 16
SET JIT = OFF
SET enable_hashjoin = OFF
SET plan_cache_mode = force_custom_plan
AS
$$
DECLARE
  _block_range hive.blocks_range := hive.convert_to_blocks_range("from-block","to-block");
  allowed_ids INT[] := ARRAY[0, 1, 17, 19, 51, 52, 53, 61, 63, 72, 73];
  _operation_types INT[];
  _calculate_total_pages INT;
  _ops_count INT;
BEGIN
IF NOT (SELECT blocksearch_indexes FROM hafbe_app.app_status LIMIT 1) THEN
  RAISE EXCEPTION 'Commentsearch indexes are not installed';
END IF;

IF "operation-types" IS NULL THEN
  "operation-types" := '0, 1, 17, 19, 51, 52, 53, 61, 63, 72, 73'::TEXT;
END IF;

_operation_types := (SELECT string_to_array("operation-types", ',')::INT[]);

IF NOT _operation_types <@ allowed_ids THEN
    RAISE EXCEPTION 'Invalid operation ID detected. Allowed IDs are: %', allowed_ids;
END IF;

IF _block_range.last_block <= hive.app_get_irreversible_block() AND _block_range.last_block IS NOT NULL THEN
  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=31536000"}]', true);
ELSE
  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);
END IF;

  --count for given parameters 
  SELECT hafbe_backend.get_comment_operations_count(
    "account-name",
    "permlink",
    _operation_types,
    _block_range.first_block,
    _block_range.last_block
  ) INTO _ops_count;

  --amount of pages
  SELECT 
    (
      CASE WHEN (_ops_count % "page-size") = 0 THEN 
        _ops_count/"page-size" 
      ELSE ((_ops_count/"page-size") + 1) 
      END
    )::INT INTO _calculate_total_pages;

RETURN (
  SELECT json_build_object(
    'total_operations', _ops_count,
    'total_pages', _calculate_total_pages,
    'operations_result', 
    (SELECT COALESCE(to_json(array_agg(row)), '[]') FROM (
      SELECT * FROM hafbe_backend.get_comment_operations("account-name", "permlink", "page", "page-size", _operation_types, _block_range.first_block, _block_range.last_block, "data-size-limit")
    ) row)
  ));

END
$$;

RESET ROLE;
