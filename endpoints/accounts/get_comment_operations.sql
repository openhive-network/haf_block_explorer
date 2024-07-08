SET ROLE hafbe_owner;

/** openapi:paths
/accounts/{account-name}/operations/comments:
  get:
    tags:
      - Accounts
    summary: Get comment related operations
    description: |
      List operations related to account and optionally filtered by permlink,
      time/blockrange and comment related operations

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_comment_operations('blocktrades');`

      * `SELECT * FROM hafbe_endpoints.get_comment_operations('gtg');`
      
      REST call example
      * `GET https://{hafbe-host}/hafbe/accounts/blocktrades/operations/comments`
      
      * `GET https://{hafbe-host}/hafbe/accounts/gtg/operations/comments`
    operationId: hafbe_endpoints.get_comment_operations
    parameters:
      - in: path
        name: account-name
        required: true
        schema:
          type: string
        description: Filter operations by the account that created them
      - in: query
        name: operation-types
        required: false
        schema:
          type: string
          x-sql-default-value: "'0, 1, 17, 19, 51, 52, 53, 61, 63, 72, 73'"
        description: |
          List of operations: if the parameter is NULL, all operations will be included
          sql example: `'18,12'`
      - in: query
        name: page
        required: false
        schema:
          type: integer
          default: 1
        description: Return page on `page` number
      - in: query
        name: permlink
        required: false
        schema:
          type: string
          default: NULL
        description: |
            Unique post identifier containing post's title and generated number
      - in: query
        name: page-size
        required: false
        schema:
          type: integer
          default: 100
        description: Return max `page-size` operations per page
      - in: query
        name: data-size-limit
        required: false
        schema:
          type: integer
          default: 200000
        description: |
          If the operation length exceeds the `data-size-limit`,
          the operation body is replaced with a placeholder
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
          Result contains total operations number,
          total pages and the list of operations

          * Returns `JSON`
        content:
          application/json:
            schema:
              type: string
              x-sql-datatype: JSON
            example:  
              - {
                  "total_operations": 1,
                  "total_pages": 1,
                  "operations_result":[
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
      '404':
        description: No such account in the database
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_comment_operations;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_comment_operations(
    "account-name" TEXT,
    "operation-types" TEXT = '0, 1, 17, 19, 51, 52, 53, 61, 63, 72, 73',
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
  _operation_types INT[] := (SELECT string_to_array("operation-types", ',')::INT[]);
BEGIN
IF NOT (SELECT blocksearch_indexes FROM hafbe_app.app_status LIMIT 1) THEN
  RAISE EXCEPTION 'Commentsearch indexes are not installed';
END IF;

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
