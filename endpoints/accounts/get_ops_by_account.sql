SET ROLE hafbe_owner;

/** openapi:paths
/accounts/{account-name}/operations:
  get:
    tags:
      - Accounts
    summary: Get operations for an account
    description: |
      List the operations in the reversed  order (first page is the oldest) for given account. 
      The page size determines the number of operations per page

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_ops_by_account(''blocktrades'');`

      REST call example
      * `GET ''https://%1$s/hafbe/accounts/blocktrades/operations?page-size=3''`
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
          example: `18,12`
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
        description: Return max `page-size` operations per page, defaults to `100`
      - in: query
        name: data-size-limit
        required: false
        schema:
          type: integer
          default: 200000
        description: |
          If the operation length exceeds the data size limit,
          the operation body is replaced with a placeholder, defaults to `200000`
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
                  "total_operations": 219867,
                  "total_pages": 73289,
                  "operations_result": [
                    {
                      "operation_id": "21474823595099394",
                      "block_num": 4999997,
                      "trx_in_block": 3,
                      "trx_id": "e75f833ceb62570c25504b55d0f23d86d9d76423",
                      "op_pos": 0,
                      "op_type_id": 2,
                      "operation": {
                        "type": "transfer_operation",
                        "value": {
                          "to": "blocktrades",
                          "from": "mrwang",
                          "memo": "a79c09cd-0084-4cd4-ae63-bf6d2514fef9",
                          "amount": {
                            "nai": "@@000000013",
                            "amount": "1633",
                            "precision": 3
                          }
                        }
                      },
                      "virtual_op": false,
                      "timestamp": "2016-09-15T19:47:12"
                    },
                    {
                      "operation_id": "21474802120262208",
                      "block_num": 4999992,
                      "trx_in_block": -1,
                      "trx_id": null,
                      "op_pos": 1,
                      "op_type_id": 64,
                      "operation": {
                        "type": "producer_reward_operation",
                        "value": {
                          "producer": "blocktrades",
                          "vesting_shares": {
                            "nai": "@@000000037",
                            "amount": "3003850165",
                            "precision": 6
                          }
                        }
                      },
                      "virtual_op": true,
                      "timestamp": "2016-09-15T19:46:57"
                    },
                    {
                      "operation_id": "21474660386343488",
                      "block_num": 4999959,
                      "trx_in_block": -1,
                      "trx_id": null,
                      "op_pos": 1,
                      "op_type_id": 64,
                      "operation": {
                        "type": "producer_reward_operation",
                        "value": {
                          "producer": "blocktrades",
                          "vesting_shares": {
                            "nai": "@@000000037",
                            "amount": "3003868105",
                            "precision": 6
                          }
                        }
                      },
                      "virtual_op": true,
                      "timestamp": "2016-09-15T19:45:12"
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
  ASSERT "from-block" IS NOT NULL, 'No block found for the given start-date';
END IF;
IF "end-date" IS NOT NULL THEN  
  "to-block" := (SELECT num FROM hive.blocks_view bv WHERE bv.created_at < "end-date" ORDER BY created_at DESC LIMIT 1);
  ASSERT "to-block" IS NOT NULL, 'No block found for the given end-date';
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
