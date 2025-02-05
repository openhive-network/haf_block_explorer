SET ROLE hafbe_owner;

/** openapi:paths
/accounts/{account-name}/operations/comments/{permlink}:
  get:
    tags:
      - Accounts
    summary: Get comment-related operations for an author-permlink.
    description: |
      List operations related to account. Optionally filtered by permlink,
      time/blockrange, and specific comment-related operations.

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_comment_operations(''blocktrades'',''blocktrades-witness-report-for-3rd-week-of-august'',''0'',1,3);`
      
      REST call example
      * `GET ''https://%1$s/hafbe-api/accounts/blocktrades/operations/comments/blocktrades-witness-report-for-3rd-week-of-august?page-size=3&operation-types=0''`
    operationId: hafbe_endpoints.get_comment_operations
    parameters:
      - in: path
        name: account-name
        required: true
        schema:
          type: string
        description: Account to get operations for
      - in: path
        name: permlink
        required: true
        schema:
          type: string
        description: |
          Unique post identifier containing post''s title and generated number
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
        name: page-size
        required: false
        schema:
          type: integer
          default: 100
        description: Return max `page-size` operations per page, defaults to `100`
      - in: query
        name: direction
        required: false
        schema:
          $ref: '#/components/schemas/hafbe_types.sort_direction'
          default: asc
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
          If the operation length exceeds the `data-size-limit`,
          the operation body is replaced with a placeholder (defaults to `200000`).
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
      '404':
        description: No such account in the database
 */
-- openapi-generated-code-begin
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
  _calculate_total_pages INT;
  _ops_count INT;
BEGIN

PERFORM hafbe_exceptions.validate_limit("page-size", 10000);
PERFORM hafbe_exceptions.validate_negative_limit("page-size");
PERFORM hafbe_exceptions.validate_negative_page("page");


IF NOT hafbe_app.isCommentSearchIndexesCreated() THEN
  RAISE EXCEPTION 'Comment search indexes are not installed';
END IF;

IF "operation-types" IS NULL THEN
  "operation-types" := '0, 1, 17, 19, 51, 52, 53, 61, 63, 72, 73'::TEXT;
END IF;

_operation_types := (SELECT string_to_array("operation-types", ',')::INT[]);

IF NOT _operation_types <@ allowed_ids THEN
  RAISE EXCEPTION 'Invalid operation ID detected. Allowed IDs are: %', allowed_ids;
END IF;

PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

--count for given parameters 
SELECT hafbe_backend.get_comment_operations_count(
  "account-name",
  "permlink",
  _operation_types
) INTO _ops_count;

--amount of pages
SELECT (
    CASE WHEN (_ops_count % "page-size") = 0 THEN 
      _ops_count/"page-size" 
    ELSE ((_ops_count/"page-size") + 1) 
    END
  )::INT INTO _calculate_total_pages;

PERFORM hafbe_exceptions.validate_page("page", _calculate_total_pages);

RETURN (
  SELECT json_build_object(
    'total_operations', _ops_count,
    'total_pages', _calculate_total_pages,
    'operations_result', 
    (SELECT COALESCE(to_json(array_agg(row)), '[]') FROM (
      SELECT * FROM hafbe_backend.get_comment_operations(
        "account-name",
        "permlink",
        _operation_types,
        "page",
        "page-size",
        "direction",
        "data-size-limit"
      )
    ) row)
  ));

END
$$;

RESET ROLE;
