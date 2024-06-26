SET ROLE hafbe_owner;

/** openapi:paths
/hafbe/accounts/{account-name}/operations:
  get:
    tags:
      - Accounts
    summary: Get operations for an account
    description: |
      List the operations in the reversed  order (first page is the oldest) for given account. 
      The page size determines the number of operations per page

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_ops_by_account('blocktrades');`

      * `SELECT * FROM hafbe_endpoints.get_ops_by_account('gtg');`

      REST call example
      * `GET https://{hafbe-host}/hafbe/accounts/blocktrades/operations`
      
      * `GET https://{hafbe-host}/hafbe/accounts/gtg/operations`
    operationId: hafbe_endpoints.get_ops_by_account
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
          default: NULL
        description: |
          List of operations: if the parameter is empty, all operations will be included
          sql example: `'18,12'`
      - in: query
        name: page
        required: false
        schema:
          type: integer
          default: NULL
        description: |
          Return page on `page` number, default null due to reversed order of pages
          the first page is the oldest
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
          If the operation length exceeds the data size limit,
          the operation body is replaced with a placeholder
      - in: query
        name: from-block
        required: false
        schema:
          type: integer
          default: NULL
        description: Lower limit of the block range
      - in: query
        name: to-block
        required: false
        schema:
          type: integer
          default: NULL
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

      '404':
        description: No such account in the database
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_ops_by_account;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_ops_by_account(
    "account-name" TEXT,
    "operation-types" TEXT = NULL,
    "page" INT = NULL,
    "page-size" INT = 100,
    "data-size-limit" INT = 200000,
    "from-block" INT = NULL,
    "to-block" INT = NULL,
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
-- force_custom_plan added to every function that uses OFFSET
AS
$$
DECLARE 
  _ops_count BIGINT;
  _calculate_total_pages INT; 
  _operation_types INT[] := (SELECT string_to_array("operation-types", ',')::INT[]);
BEGIN
IF "start-date" IS NOT NULL THEN
  "from-block" := (SELECT num FROM hive.blocks_view bv WHERE bv.created_at >= "start-date" ORDER BY created_at ASC LIMIT 1);
END IF;
IF "end-date" IS NOT NULL THEN  
  "to-block" := (SELECT num FROM hive.blocks_view bv WHERE bv.created_at < "end-date" ORDER BY created_at DESC LIMIT 1);
END IF;

SELECT hafbe_backend.get_account_operations_count(_operation_types, "account-name", "from-block", "to-block") INTO _ops_count;

SELECT (CASE WHEN (_ops_count % "page-size") = 0 THEN 
    _ops_count/"page-size" ELSE ((_ops_count/"page-size") + 1) END)::INT INTO _calculate_total_pages;

IF "to-block" <= hive.app_get_irreversible_block() OR ("page" IS NOT NULL AND _calculate_total_pages != "page") THEN
  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=31536000"}]', true);
ELSE
  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);
END IF;

RETURN (
  SELECT json_build_object(
-- ops_count returns number of operations found with current filter
    'total_operations', _ops_count,
-- to count total_pages we need to check if there was a rest from division by "page-size", if there was the page count is +1 
    'total_pages', _calculate_total_pages,
    'operations_result', 
    (SELECT to_json(array_agg(row)) FROM (
      SELECT * FROM hafbe_backend.get_ops_by_account("account-name", 
-- there is two diffrent page_nums, internal and external, internal page_num is ascending (first page with the newest operation is number 1)
-- external page_num is descending, its given by FE and recalculated by this query to internal 

-- to show the first page on account_page on FE we take page_num as NULL, because FE on the first use of the endpoint doesn't know the ops_count
-- For example query returns 15 pages and FE asks for:
-- page 15 (external first page) 15 - 15 + 1 = 1 (internal first page)
-- page 14 (external second page) 15 - 14 + 1 = 2 (internal second page)
-- ... page 7, 15 - 7 + 1 =  9 (internal 9th page)
      (CASE WHEN "page" IS NULL THEN 1 ELSE ((_calculate_total_pages - "page") + 1) END)::INT,
      "page-size",
      _operation_types,
      "from-block",
      "to-block",
      "data-size-limit",
       (_ops_count % "page-size")::INT,
       _ops_count::INT)

-- to return the first page with the rest of the division of ops count the number is handed over to backend function
    ) row)
  ));

END
$$;

RESET ROLE;
