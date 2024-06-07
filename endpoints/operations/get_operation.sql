SET ROLE hafbe_owner;

/** openapi:paths
/hafbe/operations/{operation-id}:
  get:
    tags:
      - Operations
    summary: Get informations about the operation
    description: |
      Get operation's body and its extended parameters

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_operation(3448858738752);`
      
      REST call example
      * `GET https://{hafbe-host}/hafbe/operations/3448858738752`
    operationId: hafbe_endpoints.get_operation
    parameters:
      - in: path
        name: operation-id
        required: true
        schema:
          type: integer
          x-sql-datatype: BIGINT
        description: Unique operation identifier 
    responses:
      '200':
        description: |
          Operation parameters

          * Returns `hafbe_types.operation`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hafbe_types.operation'
            example:
              - operation_id: 4294967376
                block_num: 1
                trx_in_block: -1
                trx_id: null
                op_pos: 1
                op_type_id: 80
                operation: 
                  {
                    "type": "account_created_operation",
                    "value": {
                      "creator": "miners",
                      "new_account_name": "miners",
                      "initial_delegation": {
                        "nai": "@@000000037",
                        "amount": "0",
                        "precision": 6
                      },
                      "initial_vesting_shares": {
                        "nai": "@@000000037",
                        "amount": "0",
                        "precision": 6
                      }
                    }
                  }
                virtual_op: true
                timestamp: '2016-03-24T16:00:00'
                ag": '2995 days 00:02:08.146978'
                is_modified: false
      '404':
        description: No such operation
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_operation;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_operation(
    "operation-id" BIGINT
)
RETURNS hafbe_types.operation 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
DECLARE
 _block_num INT := (SELECT ov.block_num FROM hive.operations_view ov WHERE ov.id = "operation-id");
BEGIN

IF _block_num <= hive.app_get_irreversible_block() THEN
  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=31536000"}]', true);
ELSE
  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);
END IF;

RETURN (
  SELECT ROW (
      ov.id,
      ov.block_num,
      ov.trx_in_block,
      encode(htv.trx_hash, 'hex'),
      ov.op_pos,
      ov.op_type_id,
      ov.body,
      hot.is_virtual,
      ov.timestamp,
      NOW() - ov.timestamp,
  	  FALSE)
    FROM hive.operations_view ov
    JOIN hive.operation_types hot ON hot.id = ov.op_type_id
    LEFT JOIN hive.transactions_view htv ON htv.block_num = ov.block_num AND htv.trx_in_block = ov.trx_in_block
	  WHERE ov.id = "operation-id"
);

END
$$;

RESET ROLE;
