SET ROLE hafbe_owner;

/** openapi:paths
/hafbe/block-numbers:
  get:
    tags:
      - Blocks
    summary: Get block numbers by filter
    description: |
      List the block numbers that match given operation type filter,
      account name and time/block range in specified order

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_block_by_op(ARRAY[14]);`

      * `SELECT * FROM hafbe_endpoints.get_block_by_op();`

      REST call example
      * `GET https://{hafbe-host}/hafbe/block-numbers?operation-types={14}`

      * `GET https://{hafbe-host}/hafbe/block-numbers`
    operationId: hafbe_endpoints.get_block_by_op
    parameters:
      - in: query
        name: operation-types
        required: false
        schema:
          type: array
          items:
            type: integer
          x-sql-datatype: INT[]
          default: NULL
        description: |
          List of operations: if the parameter is NULL, all operations will be included
          sql example: `ARRAY[18]`
      - in: query
        name: account-name
        required: false
        schema:
          type: string
          default: NULL
        description: Filter operations by the account that created them
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
          type: array
          items:
            type: string
          x-sql-datatype: TEXT[]
          default: NULL
        description: |
          A parameter specifying the desired value related to the set-of-keys
          sql example: `ARRAY['follow']`
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
        name: limit
        required: false
        schema:
          type: integer
          default: 100
        description: Limits the result to `limit` records
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
              - block_num: 5000000
                op_type_id: [9,5,64,80]
              - block_num: 4999999
                op_type_id: [64,30,6,0,85,72,78]
              - block_num: 4999998
                op_type_id: [1,64,0,72]
      '404':
        description: No operations in database
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_block_by_op;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_block_by_op(
    "operation-types" INT[] = NULL,
    "account-name" TEXT = NULL,
    "set-of-keys" JSON = NULL,
    "key-content" TEXT[] = NULL,
    "direction" hafbe_types.sort_direction = 'desc',
    "from-block" INT = 0,
    "to-block" INT = 2147483647,
    "start-date" TIMESTAMP = NULL,
    "end-date" TIMESTAMP = NULL,
    "limit" INT = 100
)
RETURNS SETOF hafbe_types.block_by_ops 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET plan_cache_mode = force_custom_plan
AS
$$
BEGIN
IF NOT (SELECT blocksearch_indexes FROM hafbe_app.app_status LIMIT 1) THEN
  RAISE EXCEPTION 'Blocksearch indexes are not installed';
END IF;

IF "key-content" IS NOT NULL THEN
  IF array_length("operation-types", 1) != 1 THEN 
    RAISE EXCEPTION 'Invalid set of operations, use single operation. ';
  END IF;
  
  FOR i IN 0 .. json_array_length("set-of-keys")-1 LOOP
	  IF NOT ARRAY(SELECT json_array_elements_text("set-of-keys"->i)) = ANY(SELECT * FROM hafbe_endpoints.get_operation_keys((SELECT unnest("operation-types")))) THEN
	  RAISE EXCEPTION 'Invalid key %', "set-of-keys"->i;
    END IF;
  END LOOP;
END IF;

IF "operation-types" IS NULL THEN
  SELECT array_agg(id) FROM hive.operation_types INTO "operation-types";
END IF;

IF "start-date" IS NOT NULL THEN
  "from-block" := (SELECT num FROM hive.blocks_view bv WHERE bv.created_at >= "start-date" ORDER BY created_at ASC LIMIT 1);
END IF;
IF "end-date" IS NOT NULL THEN  
  "to-block" := (SELECT num FROM hive.blocks_view bv WHERE bv.created_at < "end-date" ORDER BY created_at DESC LIMIT 1);
END IF;

IF "to-block" <= hive.app_get_irreversible_block() THEN
  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=31536000"}]', true);
ELSE
  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);
END IF;

IF array_length("operation-types", 1) = 1 THEN
  RETURN QUERY 
      SELECT * FROM hafbe_backend.get_block_by_single_op(
        "operation-types"[1], "account-name", "direction", "from-block", "to-block", "limit", "key-content", "set-of-keys"
      )
  ;

ELSE
  RETURN QUERY
      SELECT * FROM hafbe_backend.get_block_by_ops_group_by_block_num(
        "operation-types", "account-name", "direction", "from-block", "to-block", "limit"
      )
  ;

END IF;
END
$$;

RESET ROLE;
