SET ROLE hafbe_owner;

/** openapi:paths
/blocks/{block-num}/operations:
  get:
    tags:
      - Blocks
    summary: Get operations in block
    description: |
      List the operations in the specified order that are within the given block number. 
      The page size determines the number of operations per page

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_ops_by_block_paging(10000);`

      * `SELECT * FROM hafbe_endpoints.get_ops_by_block_paging(43000,ARRAY[0,1]);`
      
      REST call example
      * `GET https://{hafbe-host}/hafbe/blocks/10000/operations`

      * `GET https://{hafbe-host}/hafbe/blocks/43000/operations?operation-types=0,1`
    operationId: hafbe_endpoints.get_ops_by_block_paging
    parameters:
      - in: path
        name: block-num
        required: true
        schema:
          type: integer
        description: List operations from given block number
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
        name: account-name
        required: false
        schema:
          type: string
          default: NULL
        description: Filter operations by the account that created them
      - in: query
        name: page
        required: false
        schema:
          type: integer
          default: 1
        description: Return page on `page` number
      - in: query
        name: page-size
        required: false
        schema:
          type: integer
          default: 100
        description: Return max `page-size` operations per page
      - in: query
        name: set-of-keys
        required: false
        schema:
          type: string
          x-sql-datatype: JSON
          default: NULL
        description: |
          A JSON object detailing the path to the filtered key specified in key-content
          sql example: `[["value", "id"]]`
      - in: query
        name: key-content
        required: false
        schema:
          type: string
          default: NULL
        description: |
          A parameter specifying the desired value related to the set-of-keys
          sql example: `'follow'`
      - in: query
        name: direction
        required: false
        schema:
          $ref: '#/components/schemas/hafbe_types.sort_direction'
          default: desc
        description: |
          Sort order:

           * `asc` - Ascending, from A to Z or smallest to largest
           
           * `desc` - Descending, from Z to A or largest to smallest
      - in: query
        name: data-size-limit
        required: false
        schema:
          type: integer
          default: 200000
        description: |
          If the operation length exceeds the data size limit,
          the operation body is replaced with a placeholder
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
        description: The result is empty
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_ops_by_block_paging;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_ops_by_block_paging(
    "block-num" INT,
    "operation-types" TEXT = NULL,
    "account-name" TEXT = NULL,
    "page" INT = 1,
    "page-size" INT = 100,
    "set-of-keys" JSON = NULL,
    "key-content" TEXT = NULL,
    "direction" hafbe_types.sort_direction = 'desc',
    "data-size-limit" INT = 200000
)
RETURNS JSON 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
SET JIT = OFF
SET join_collapse_limit = 16
SET from_collapse_limit = 16
AS
$$
DECLARE
  _operation_types INT[] := NULL;
  _key_content TEXT[] := NULL;
  _set_of_keys JSON := NULL;
BEGIN
IF "key-content" IS NOT NULL THEN
  IF "operation-types" IS NOT NULL THEN
    _operation_types := string_to_array("operation-types", ',')::INT[];
  END IF;

  _key_content := string_to_array("key-content", ',')::TEXT[];
  _set_of_keys := replace(replace(replace("set-of-keys"::TEXT, '"[', '['), ']"', ']'), '\"', '"')::JSON;
END IF;

IF "block-num" <= hive.app_get_irreversible_block() THEN
  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=31536000"}]', true);
ELSE
  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);
END IF;

RETURN (
  WITH ops_count AS MATERIALIZED (
    SELECT * FROM hafbe_backend.get_ops_by_block_count("block-num", _operation_types, "account-name", _key_content, _set_of_keys)
  ),
  calculate_total_pages AS MATERIALIZED (
    SELECT 
      (CASE 
        WHEN ((SELECT * FROM ops_count) % "page-size") = 0 THEN 
          (SELECT * FROM ops_count)/"page-size" 
        ELSE 
          (((SELECT * FROM ops_count)/"page-size") + 1) END)
  )
  SELECT json_build_object(
    'total_operations', (SELECT * FROM ops_count),
    'total_pages', (SELECT * FROM calculate_total_pages),
    'operations_result', 
    (SELECT to_json(array_agg(row)) FROM (
      SELECT * FROM hafbe_backend.get_ops_by_block(
      "block-num", 
      "page",
      "page-size",
      _operation_types,
      "direction",
      "data-size-limit",
      "account-name",
      _key_content,
      _set_of_keys
      )
    ) row)
  ));

END
$$;

RESET ROLE;
