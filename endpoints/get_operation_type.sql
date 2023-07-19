CREATE OR REPLACE FUNCTION hafbe_endpoints.format_op_types(op_type_id INT, _operation_name TEXT, _is_virtual BOOLEAN)
RETURNS JSON
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN ('[' || op_type_id || ', "' || split_part(_operation_name, '::', 3) || '", ' || _is_virtual || ']');
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_matching_operation_types(_operation_type_pattern TEXT)
RETURNS JSON
LANGUAGE 'plpgsql' STABLE
AS
$$
DECLARE
  __operation_name TEXT = '%' || _operation_type_pattern || '%';
BEGIN
  RETURN CASE WHEN res.arr IS NOT NULL THEN res.arr ELSE '[]'::JSON END FROM (
    SELECT json_agg(hafbe_endpoints.format_op_types(op_type_id,operation_name, is_virtual)) AS arr
    FROM hafbe_backend.get_set_of_op_types_by_name(__operation_name)
  ) res;
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_op_types()
RETURNS JSON
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN CASE WHEN res.arr IS NOT NULL THEN res.arr ELSE '[]'::JSON END FROM (
    SELECT json_agg(hafbe_endpoints.format_op_types(op_type_id, operation_name, is_virtual)) AS arr
    FROM hafbe_backend.get_set_of_op_types()
  ) res;
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_acc_op_types(_account TEXT)
RETURNS JSON
LANGUAGE 'plpgsql' STABLE
AS
$$
DECLARE
  __account_id INT = hafbe_backend.get_account_id(_account);
BEGIN
  RETURN CASE WHEN res.arr IS NOT NULL THEN res.arr ELSE '[]'::JSON END FROM (
    SELECT json_agg(hafbe_endpoints.format_op_types(op_type_id, operation_name, is_virtual)) AS arr
    FROM hafbe_backend.get_set_of_acc_op_types(__account_id)
  ) res;
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_block_op_types(_block_num INT)
RETURNS JSON
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN CASE WHEN res.arr IS NOT NULL THEN res.arr ELSE '[]'::JSON END FROM (
    SELECT json_agg(hafbe_endpoints.format_op_types(op_type_id, operation_name, is_virtual)) AS arr
    FROM hafbe_backend.get_set_of_block_op_types(_block_num)
  ) res;
END
$$
;
