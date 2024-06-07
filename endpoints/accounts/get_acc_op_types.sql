SET ROLE hafbe_owner;

/** openapi:paths
/hafbe/accounts/{account-name}/operation-types:
  get:
    tags:
      - Accounts
    summary: Lists operation types
    description: |
      Lists all types of operations that the account has performed since its creation

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_acc_op_types('blocktrades');`

      * `SELECT * FROM hafbe_endpoints.get_acc_op_types('initminer');`

      REST call example
      * `GET https://{hafbe-host}/hafbe/accounts/blocktrades/operation-types`
      
      * `GET https://{hafbe-host}/hafbe/accounts/initminer/operation-types`
    operationId: hafbe_endpoints.get_acc_op_types
    parameters:
      - in: path
        name: account-name
        required: true
        schema:
          type: string
        description: Name of the account
    responses:
      '200':
        description: |
          Operation type list

          * Returns array of `hafbe_types.op_types`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hafbe_types.array_of_op_types'
            example:
              - op_type_id: 72
                operation_name: effective_comment_vote_operation
                is_virtual: true
              - op_type_id: 0
                operation_name: vote_operation
                is_virtual: false
      '404':
        description: No such account in the database
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_acc_op_types;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_acc_op_types(
    "account-name" TEXT
)
RETURNS SETOF hafbe_types.op_types 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
SET JIT = OFF
SET join_collapse_limit = 16
SET from_collapse_limit = 16
AS
$$
DECLARE
  __account_id INT = hafbe_backend.get_account_id("account-name");
BEGIN

PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

RETURN QUERY WITH op_types_cte AS (
  SELECT id
  FROM hive.operation_types hot
  WHERE (
    SELECT EXISTS (
      SELECT 1 FROM hive.account_operations_view aov WHERE aov.account_id = __account_id AND aov.op_type_id = hot.id)))

SELECT cte.id::INT, split_part( hot.name, '::', 3), hot.is_virtual
FROM op_types_cte cte
JOIN hive.operation_types hot ON hot.id = cte.id
;

END
$$;

RESET ROLE;
