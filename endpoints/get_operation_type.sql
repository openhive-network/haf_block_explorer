SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_matching_operation_types(_operation_type_pattern TEXT)
RETURNS SETOF hafbe_types.op_types -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
AS
$$
DECLARE
  __operation_name TEXT = '%' || _operation_type_pattern || '%';
BEGIN
RETURN QUERY SELECT
  id, split_part(name, '::', 3), is_virtual
FROM hive.operation_types
WHERE name LIKE __operation_name
ORDER BY id ASC
;

END
$$;

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_op_types()
RETURNS SETOF hafbe_types.op_types -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
RETURN QUERY SELECT
  id, split_part(name, '::', 3), is_virtual
FROM hive.operation_types
ORDER BY id ASC
;

END
$$;

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_acc_op_types(_account TEXT)
RETURNS SETOF hafbe_types.op_types -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
SET JIT = OFF
SET join_collapse_limit = 16
SET from_collapse_limit = 16
AS
$$
DECLARE
  __account_id INT = hafbe_backend.get_account_id(_account);
BEGIN
RETURN QUERY WITH op_types_cte AS (
  SELECT id
  FROM hive.operation_types hot
  WHERE (
    SELECT EXISTS (
      SELECT 1 FROM hive.account_operations_view haov WHERE haov.account_id = __account_id AND haov.op_type_id = hot.id)))

SELECT cte.id, split_part( hot.name, '::', 3), hot.is_virtual
FROM op_types_cte cte
JOIN hive.operation_types hot ON hot.id = cte.id
;

END
$$;

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_block_op_types(_block_num INT)
RETURNS SETOF hafbe_types.op_types -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
SET JIT = OFF
SET join_collapse_limit = 16
SET from_collapse_limit = 16
AS
$$
BEGIN
RETURN QUERY SELECT DISTINCT ON (hov.op_type_id)
  hov.op_type_id, split_part( hot.name, '::', 3), hot.is_virtual
FROM hive.operations_view hov
JOIN hive.operation_types hot ON hot.id = hov.op_type_id
WHERE hov.block_num = _block_num
ORDER BY hov.op_type_id ASC
;

END
$$;

RESET ROLE;
