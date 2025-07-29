SET ROLE hafbe_owner;

/** openapi:paths
/block-search:
  get:
    tags:
      - Block-search
    summary: List block stats that match operation type filter, account name, and time/block range.
    description: |
      List the block stats that match given operation type filter,
      account name and time/block range in specified order

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_block_by_op(NULL,NULL,NULL,5);`

      REST call example
      * `GET ''https://%1$s/hafbe-api/block-search?page-size=5''`
    operationId: hafbe_endpoints.get_block_by_op
    parameters:
      - in: query
        name: operation-types
        required: false
        schema:
          type: string
          default: NULL
        description: |
          List of operations: if the parameter is NULL, all operations will be included.
          example: `18,12`
      - in: query
        name: account-name
        required: false
        schema:
          type: string
          default: NULL
        description: Filter operations by the account that created them.
      - in: query
        name: page
        required: false
        schema:
          type: integer
          default: NULL
        description: Return page on `page` number, defaults to `NULL`
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
          default: desc
        description: |
          Sort order:
          
           * `asc` - Ascending, from A to Z or smallest to largest

           * `desc` - Descending, from Z to A or largest to smallest
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
      - in: query
        name: path-filter
        required: false
        schema:
          type: array
          items:
            type: string
          x-sql-datatype: TEXT[]
          default: NULL
        description: |
          A parameter specifying the desired value in operation body,
          example: `value.creator=alpha`
    responses:
      '200':
        description: |
          Block number with filtered operations

          * Returns `hafbe_types.block_history`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hafbe_types.block_history'
            example: {
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
      '404':
        description: No operations in database
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_block_by_op;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_block_by_op(
    "operation-types" TEXT = NULL,
    "account-name" TEXT = NULL,
    "page" INT = NULL,
    "page-size" INT = 100,
    "direction" hafbe_types.sort_direction = 'desc',
    "from-block" TEXT = NULL,
    "to-block" TEXT = NULL,
    "path-filter" TEXT[] = NULL
)
RETURNS hafbe_types.block_history 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
AS
$$
DECLARE
  _block_range hive.blocks_range    := hive.convert_to_blocks_range("from-block","to-block");
  _account_id INT                   := hafah_backend.get_account_id("account-name", FALSE);
  _head_block_num INT               := hafbe_backend.get_hafbe_head_block();
  _operation_types INT[]            := hafah_backend.get_operation_types("operation-types", TRUE);

  _key_content TEXT[]               := NULL;
  _set_of_keys JSON                 := NULL;
BEGIN
  PERFORM hafbe_exceptions.validate_limit("page-size", 1000);
  PERFORM hafbe_exceptions.validate_negative_limit("page-size");
  PERFORM hafbe_exceptions.validate_negative_page("page");
  PERFORM hafbe_exceptions.validate_block_num_too_high(_block_range.first_block, _head_block_num);

  IF hafah_backend.is_path_filter_not_empty("path-filter") THEN
    -- if path-filter is not empty, validate if extra indexes are available
    -- and if the operation type is single
    PERFORM hafbe_exceptions.validate_block_search_indexes();
    PERFORM hafbe_exceptions.validate_single_operation_type(_operation_types);

    SELECT param_json::JSON, param_text::TEXT[]
    INTO _set_of_keys, _key_content
    FROM hafah_backend.parse_path_filters("path-filter");

    PERFORM hafbe_exceptions.validate_path_filter_keys(_operation_types, _set_of_keys);
  END IF;

  IF _block_range.last_block <= hive.app_get_irreversible_block() AND _block_range.last_block IS NOT NULL THEN
    PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=31536000"}]', true);
  ELSE
    PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);
  END IF;

  RETURN hafbe_backend.get_blocks_by_ops(
    _operation_types,
    _account_id,
    "direction",
    _block_range.first_block,
    _block_range.last_block,
    "page",
    "page-size",
    _key_content,
    _set_of_keys
  );

END
$$;

RESET ROLE;
