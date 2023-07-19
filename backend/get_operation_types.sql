
CREATE OR REPLACE FUNCTION hafbe_backend.get_set_of_op_types()
RETURNS SETOF hafbe_types.op_types
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN QUERY SELECT
    id, name, is_virtual
  FROM hive.operation_types
  ORDER BY id ASC;
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_backend.get_set_of_op_types_by_name(_operation_name TEXT)
RETURNS SETOF hafbe_types.op_types
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN QUERY SELECT
    id, name, is_virtual
  FROM hive.operation_types
  WHERE name LIKE _operation_name
  ORDER BY id ASC;
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_backend.get_set_of_acc_op_types(_account_id INT)
RETURNS SETOF hafbe_types.op_types
AS
$function$
BEGIN
  RETURN QUERY WITH op_types_cte AS (
    SELECT id
    FROM hive.operation_types hot
    WHERE (
      SELECT EXISTS (
        SELECT 1 FROM hive.account_operations_view haov WHERE haov.account_id = _account_id AND haov.op_type_id = hot.id
      )
    )
  )

  SELECT cte.id, hot.name, hot.is_virtual
  FROM op_types_cte cte
  JOIN hive.operation_types hot ON hot.id = cte.id;
END
$function$
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
;

CREATE OR REPLACE FUNCTION hafbe_backend.get_set_of_block_op_types(_block_num INT)
RETURNS SETOF hafbe_types.op_types
AS
$function$
BEGIN
  RETURN QUERY SELECT DISTINCT ON (hov.op_type_id)
    hov.op_type_id, hot.name, hot.is_virtual
  FROM hive.operations_view hov
  JOIN hive.operation_types hot ON hot.id = hov.op_type_id
  WHERE hov.block_num = _block_num
  ORDER BY hov.op_type_id ASC;
END
$function$
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
;
