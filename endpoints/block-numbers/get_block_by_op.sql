SET ROLE hafbe_owner;

/** openapi:paths
/block-numbers:
  get:
    tags:
      - Block-numbers
    summary: List block numbers that match operation type filter, account name, and time/block range.
    description: |
      List the block numbers that match given operation type filter,
      account name and time/block range in specified order

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_block_by_op(''6'',NULL,''desc'',4999999,5000000);`

      REST call example
      * `GET ''https://%1$s/hafbe-api/block-numbers?operation-types=6&from-block=4999999&to-block5000000''`
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
        name: result-limit
        required: false
        schema:
          type: integer
          default: 100
        description: Limits the result to `result-limit` records
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

          * Returns array of `hafbe_types.block_by_ops`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hafbe_types.array_of_block_by_ops'
            example: 
              - block_num: 4999999
                op_type_id: [6]
      '404':
        description: No operations in database
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_block_by_op;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_block_by_op(
    "operation-types" TEXT = NULL,
    "account-name" TEXT = NULL,
    "direction" hafbe_types.sort_direction = 'desc',
    "from-block" TEXT = NULL,
    "to-block" TEXT = NULL,
    "result-limit" INT = 100,
    "path-filter" TEXT[] = NULL
)
RETURNS SETOF hafbe_types.block_by_ops 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET plan_cache_mode = force_custom_plan
AS
$$
DECLARE
  _block_range hive.blocks_range := hive.convert_to_blocks_range("from-block","to-block");
  _operation_types INT[] := NULL;
  _key_content TEXT[] := NULL;
  _set_of_keys JSON := NULL;
  _is_key_incorrect BOOLEAN := FALSE;
  _invalid_key TEXT := NULL;
BEGIN
IF "path-filter" IS NOT NULL AND "path-filter" != '{}' THEN
  --using path-filter requires indexes on hive.operations
  IF NOT (SELECT blocksearch_indexes FROM hafbe_app.app_status LIMIT 1) THEN
    RAISE EXCEPTION 'Blocksearch indexes are not installed';
  END IF;

  --ensure operation-type is provided when key-value is used
  IF "operation-types" IS NULL THEN
    RAISE EXCEPTION 'Operation type not specified';
  END IF;

  --decode key-value
  SELECT 
    pvpf.param_json::JSON,
    pvpf.param_text::TEXT[],
    string_to_array("operation-types", ',')::INT[]
  INTO _set_of_keys, _key_content, _operation_types
  FROM hafah_backend.parse_path_filters("path-filter") pvpf;

  --ensure that one operation is selected when keys are used
  IF array_length(_operation_types, 1) != 1 OR _operation_types IS NULL THEN 
    RAISE EXCEPTION 'Invalid set of operations, use single operation. ';
  END IF;
  
  --check if provided keys are correct
	WITH user_provided_keys AS
	(
		SELECT json_array_elements_text(_set_of_keys) AS given_key
	),
	haf_keys AS
	(
		SELECT jsonb_array_elements_text(hafah_endpoints.get_operation_keys((SELECT unnest(_operation_types)))) AS keys
	),
	check_if_given_keys_are_correct AS
	(
		SELECT up.given_key, hk.keys IS NULL AS incorrect_key
		FROM user_provided_keys up
		LEFT JOIN haf_keys hk ON replace(replace(hk.keys, ' ', ''),'\','') = replace(replace(up.given_key, ' ', ''),'\','')
	)
	SELECT given_key, incorrect_key INTO _invalid_key, _is_key_incorrect
	FROM check_if_given_keys_are_correct
	WHERE incorrect_key LIMIT 1;
	
	IF _is_key_incorrect THEN
	  RAISE EXCEPTION 'Invalid key %', _invalid_key;
	END IF;
ELSE 
  IF "operation-types" IS NOT NULL THEN
    _operation_types := string_to_array("operation-types", ',')::INT[];
  END IF;
END IF;

--if no path-filter and operation-types are used - use operation-type
IF _operation_types IS NULL THEN
  SELECT array_agg(id) FROM hive.operation_types INTO _operation_types;
END IF;

IF _block_range.last_block <= hive.app_get_irreversible_block() AND _block_range.last_block IS NOT NULL THEN
  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=31536000"}]', true);
ELSE
  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);
END IF;

IF array_length(_operation_types, 1) = 1 THEN
  RETURN QUERY 
      SELECT * FROM hafbe_backend.get_block_by_single_op(
        _operation_types[1], "account-name", "direction", _block_range.first_block, _block_range.last_block, "result-limit", _key_content, _set_of_keys
      )
  ;

ELSE
  RETURN QUERY
      SELECT * FROM hafbe_backend.get_block_by_ops_group_by_block_num(
        _operation_types, "account-name", "direction", _block_range.first_block, _block_range.last_block, "result-limit"
      )
  ;

END IF;
END
$$;

RESET ROLE;
