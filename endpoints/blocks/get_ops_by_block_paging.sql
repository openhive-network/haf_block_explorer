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
      * `SELECT * FROM hafbe_endpoints.get_ops_by_block_paging(5000000,''5,64'');`
      
      REST call example
      * `GET ''https://%1$s/hafbe/blocks/5000000/operations?operation-types=80&path-filter=value.creator=steem''`
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
          List of operations: if the parameter is empty, all operations will be included,
          example: `18,12`
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
        description: Return page on `page` number, defaults to `1`
      - in: query
        name: page-size
        required: false
        schema:
          type: integer
          default: 100
        description: Return max `page-size` operations per page, defaults to `100`
      - in: query
        name: page-order
        required: false
        schema:
          $ref: '#/components/schemas/hafbe_types.sort_direction'
          default: desc
        description: |
          page order:

           * `asc` - Ascending, from oldest to newest page
           
           * `desc` - Descending, from newest to oldest page
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
        name: path-filter
        required: false
        schema:
          type: array
          items:
            type: string
          x-sql-datatype: TEXT
          default: NULL
        description: |
          A parameter specifying the expected value in operation body,
          example: `value.creator=steem`
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
                  "operations_result": [
                    {
                      "op": {
                        "type": "account_created_operation",
                        "value": {
                          "creator": "steem",
                          "new_account_name": "kefadex",
                          "initial_delegation": {
                            "nai": "@@000000037",
                            "amount": "0",
                            "precision": 6
                          },
                          "initial_vesting_shares": {
                            "nai": "@@000000037",
                            "amount": "30038455132",
                            "precision": 6
                          }
                        }
                      },
                      "block": 5000000,
                      "trx_id": "6707feb450da66dc223ab5cb3e259937b2fef6bf",
                      "op_pos": 1,
                      "op_type_id": 80,
                      "timestamp": "2016-09-15T19:47:21",
                      "virtual_op": true,
                      "operation_id": "21474836480000336",
                      "trx_in_block": 0
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
    "page-order" hafbe_types.sort_direction = 'desc',
    "data-size-limit" INT = 200000,
    "path-filter" TEXT = NULL
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
  _path_filter TEXT[] := NULL;
BEGIN
IF "path-filter" IS NOT NULL OR "path-filter" != '' THEN

  _path_filter := string_to_array("path-filter", ',')::TEXT[];

  SELECT 
    replace(replace(replace(pvpf.param_json::TEXT, '"[', '['), ']"', ']'), '\"', '"')::JSON,
    string_to_array(pvpf.param_text, ',')::TEXT[]
  INTO _set_of_keys, _key_content
  FROM hafbe_backend.parse_path_filters(_path_filter) pvpf;
END IF;

IF "operation-types" IS NOT NULL THEN
  _operation_types := string_to_array("operation-types", ',')::INT[];
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
      "page-order",
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
