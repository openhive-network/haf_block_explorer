SET ROLE hafbe_owner;

/** openapi:components:schemas
hafbe_types.array_of_text_array:
  type: array
  items:
    type: array
    items:
        type: string
    x-sql-datatype: TEXT[]
 */

/** openapi:paths
/operation-keys/{operation-type}:
  get:
    tags:
      - Operations
    summary: Get operation json body keys
    description: |
      Lists possible json key paths in operation body for given operation type id

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_operation_keys(1);`
      
      REST call example
      * `GET https://{hafbe-host}/hafbe/operation-keys/1`
    operationId: hafbe_endpoints.get_operation_keys
    parameters:
      - in: path
        name: operation-type
        required: true
        schema:
          type: integer
        description: Unique operation identifier 
    responses:
      '200':
        description: |
          Operation json key paths

          * Returns array of `TEXT[]`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hafbe_types.array_of_text_array'
            example: 
              - ["value","body"]
              - ["value","title"]
              - ["value","author"]
              - ["value","permlink"]
              - ["value","json_metadata"]
              - ["value","parent_author"] 
              - ["value","parent_permlink"]
      '404':
        description: No such operation
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_operation_keys;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_operation_keys(
    "operation-type" INT
)
RETURNS SETOF TEXT[] 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
SET JIT = OFF
SET join_collapse_limit = 16
SET from_collapse_limit = 16
SET enable_bitmapscan = OFF
-- enable_bitmapscan = OFF helps with perfomance on database with smaller number of blocks 
-- (tested od 12m blocks, planner choses wrong plan and the query is slow)
AS
$$
DECLARE
	_example_key JSON := (SELECT ov.body FROM hive.operations_view ov WHERE ov.op_type_id = "operation-type" LIMIT 1);
BEGIN

PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=31536000"}]', true);

RETURN QUERY
WITH RECURSIVE extract_keys AS (
  SELECT 
    ARRAY['value']::TEXT[] as key_path, 
    (json_each(_example_key -> 'value')).*
  UNION ALL
  SELECT 
    key_path || key,
    (json_each(value)).*
  FROM 
    extract_keys
  WHERE 
    json_typeof(value) = 'object'
)
SELECT 
  key_path || key as full_key_path
FROM 
  extract_keys
WHERE 
  json_typeof(value) != 'object'
;

END
$$;

RESET ROLE;
