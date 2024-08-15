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
      * `GET ''https://%1$s/hafbe/accounts/blocktrades/comment-operations?page-size=2&from-block=4000000&to-block=5000000''`
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
          type: integer
          default: 0
        description: Lower limit of the block range
      - in: query
        name: to-block
        required: false
        schema:
          type: integer
          default: 2147483647
        description: Upper limit of the block range
      - in: query
        name: start-date
        required: false
        schema:
          type: string
          format: date-time
          default: NULL
        description: Lower limit of the time range
      - in: query
        name: end-date
        required: false
        schema:
          type: string
          format: date-time
          default: NULL
        description: Upper limit of the time range
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
    "from-block" INT = 0,
    "to-block" INT = 2147483647,
    "start-date" TIMESTAMP = NULL,
    "end-date" TIMESTAMP = NULL
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
  allowed_ids INT[] := ARRAY[0, 1, 17, 19, 51, 52, 53, 61, 63, 72, 73];
  _operation_types INT[];
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

IF "start-date" IS NOT NULL THEN
  "from-block" := (SELECT num FROM hive.blocks_view bv WHERE bv.created_at >= "start-date" ORDER BY created_at ASC LIMIT 1);
  ASSERT "from-block" IS NOT NULL, 'No block found for the given start-date';
END IF;
IF "end-date" IS NOT NULL THEN  
  "to-block" := (SELECT num FROM hive.blocks_view bv WHERE bv.created_at < "end-date" ORDER BY created_at DESC LIMIT 1);
  ASSERT "to-block" IS NOT NULL, 'No block found for the given end-date';
END IF;

IF "to-block" <= hive.app_get_irreversible_block() THEN
  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=31536000"}]', true);
ELSE
  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);
END IF;

RETURN (
  WITH ops_count AS MATERIALIZED (
    SELECT * FROM hafbe_backend.get_comment_operations_count("account-name", "permlink", _operation_types, "from-block", "to-block")
  )

  SELECT json_build_object(
    'total_operations', (SELECT * FROM ops_count),
    'total_pages', (SELECT * FROM ops_count)/100,
    'operations_result', 
    (SELECT to_json(array_agg(row)) FROM (
      SELECT * FROM hafbe_backend.get_comment_operations("account-name", "permlink", "page", "page-size", _operation_types, "from-block", "to-block", "data-size-limit")
    ) row)
  ));

END
$$;

RESET ROLE;
