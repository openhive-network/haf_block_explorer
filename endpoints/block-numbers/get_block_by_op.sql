SET ROLE hafbe_owner;

/** openapi:paths
/block-numbers:
  get:
    tags:
      - Block-numbers
    summary: Get block numbers by filters
    description: |
      List the block numbers that match given operation type filter,
      account name and time/block range in specified order

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_block_by_op(''6'',NULL,''desc'',4999999,5000000);`

      REST call example
      * `GET ''https://%1$s/hafbe/block-numbers?operation-types=6&from-block=4999999&to-block5000000''`
    operationId: hafbe_endpoints.get_block_by_op
    parameters:
      - in: query
        name: operation-types
        required: false
        schema:
          type: string
          default: NULL
        description: |
          List of operations: if the parameter is NULL, all operations will be included
          example: `18,12`
      - in: query
        name: account-name
        required: false
        schema:
          type: string
          default: NULL
        description: Filter operations by the account that created them
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
          example: `value.creator=steem`
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
    "from-block" INT = 0,
    "to-block" INT = 2147483647,
    "start-date" TIMESTAMP = NULL,
    "end-date" TIMESTAMP = NULL,
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
  _operation_types INT[] := NULL;
  _key_content TEXT[] := NULL;
  _set_of_keys JSON := NULL;
BEGIN
IF "path-filter" IS NOT NULL AND "path-filter" != '{}' THEN

  IF NOT (SELECT blocksearch_indexes FROM hafbe_app.app_status LIMIT 1) THEN
    RAISE EXCEPTION 'Blocksearch indexes are not installed';
  END IF;

  IF "operation-types" IS NULL THEN
    RAISE EXCEPTION 'Operation type not specified';
  END IF;

  SELECT 
    pvpf.param_json::JSON,
    pvpf.param_text::TEXT[],
    string_to_array("operation-types", ',')::INT[]
  INTO _set_of_keys, _key_content, _operation_types
  FROM hafah_backend.parse_path_filters("path-filter") pvpf;

  IF array_length(_operation_types, 1) != 1 OR _operation_types IS NULL THEN 
    RAISE EXCEPTION 'Invalid set of operations, use single operation. ';
  END IF;
  
  FOR i IN 0 .. json_array_length(_set_of_keys)-1 LOOP
	  IF NOT ARRAY(SELECT json_array_elements_text(_set_of_keys->i)) = ANY(SELECT * FROM hafbe_endpoints.get_operation_keys((SELECT unnest(_operation_types)))) THEN
	  RAISE EXCEPTION 'Invalid key %', _set_of_keys->i;
    END IF;
  END LOOP;
ELSE 
  IF "operation-types" IS NOT NULL THEN
    _operation_types := string_to_array("operation-types", ',')::INT[];
  END IF;
END IF;

IF _operation_types IS NULL THEN
  SELECT array_agg(id) FROM hive.operation_types INTO _operation_types;
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

IF array_length(_operation_types, 1) = 1 THEN
  RETURN QUERY 
      SELECT * FROM hafbe_backend.get_block_by_single_op(
        _operation_types[1], "account-name", "direction", "from-block", "to-block", "result-limit", _key_content, _set_of_keys
      )
  ;

ELSE
  RETURN QUERY
      SELECT * FROM hafbe_backend.get_block_by_ops_group_by_block_num(
        _operation_types, "account-name", "direction", "from-block", "to-block", "result-limit"
      )
  ;

END IF;
END
$$;

RESET ROLE;
