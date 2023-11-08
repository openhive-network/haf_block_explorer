SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_backend.get_block_by_single_op(_operations INT, _account TEXT, _order_is hafbe_types.order_is, _from INT, _to INT, _limit INT, _key_content TEXT[], _setof_keys JSON)
RETURNS SETOF INT
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
IF _account IS NULL THEN
  RETURN QUERY EXECUTE format(

    $query$
    SELECT DISTINCT o.block_num FROM hive.operations_view o
    WHERE 
      o.op_type_id = %L
      AND o.block_num BETWEEN %L AND %L 
      AND (CASE WHEN %L IS NOT NULL THEN
      jsonb_extract_path_text(o.body, variadic %L) = %L ELSE
      TRUE
      END)
      AND (CASE WHEN %L IS NOT NULL THEN
      jsonb_extract_path_text(o.body, variadic %L) = %L ELSE
      TRUE
      END)
      AND (CASE WHEN %L IS NOT NULL THEN
      jsonb_extract_path_text(o.body, variadic %L) = %L ELSE
      TRUE
      END)
    ORDER BY o.block_num %s
    LIMIT %L
    $query$, 

  _operations,
  _from, _to, 
  _key_content[1],
  ARRAY(SELECT json_array_elements_text(_setof_keys->0)), _key_content[1],
  _key_content[2],
  ARRAY(SELECT json_array_elements_text(_setof_keys->1)), _key_content[2], 
  _key_content[3],
  ARRAY(SELECT json_array_elements_text(_setof_keys->2)), _key_content[3], 
  _order_is, 
  _limit) res
  ;

ELSE

  RETURN QUERY EXECUTE format(
      $query$
      WITH source_account_id AS MATERIALIZED (
      SELECT a.id from hive.accounts_view a where a.name = %L),

      source_ops AS (
      SELECT array_agg(ao.operation_id) AS operation_id, ao.block_num
      FROM hive.account_operations_view ao
      WHERE 
        ao.op_type_id = %L AND 
        ao.account_id = (SELECT id FROM source_account_id) AND 
        ao.block_num BETWEEN %L AND %L
      GROUP BY ao.block_num
      ORDER BY ao.block_num %s),  

      unnest_ops AS MATERIALIZED (
      SELECT unnest(operation_id) AS operation_id
      FROM source_ops)

      SELECT DISTINCT o.block_num
      FROM hive.operations_view o
      JOIN unnest_ops s on s.operation_id = o.id
      WHERE 
        (CASE WHEN %L IS NOT NULL THEN
        jsonb_extract_path_text(o.body, variadic %L) = %L ELSE
        TRUE
        END) AND
        (CASE WHEN %L IS NOT NULL THEN
        jsonb_extract_path_text(o.body, variadic %L) = %L ELSE
        TRUE
        END) AND
        (CASE WHEN %L IS NOT NULL THEN
        jsonb_extract_path_text(o.body, variadic %L) = %L ELSE
        TRUE
        END) AND
        o.op_type_id = %L
      ORDER BY o.block_num %s
      LIMIT %L
      $query$, 

    _account, 
    _operations, 
    _from, _to, 
    _order_is, 
    _key_content[1],
    ARRAY(SELECT json_array_elements_text(_setof_keys->0)), _key_content[1],
    _key_content[2],
    ARRAY(SELECT json_array_elements_text(_setof_keys->1)), _key_content[2],
    _key_content[3],
    ARRAY(SELECT json_array_elements_text(_setof_keys->2)), _key_content[3],
    _operations, 
    _order_is, 
    _limit)
    ;

END IF;
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_backend.get_block_by_ops_group_by_op_type_id(_operations INT[], _account TEXT, _order_is hafbe_types.order_is, _from INT, _to INT, _limit INT)
RETURNS SETOF hafbe_types.get_block_by_ops_group_by_op_type_id
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
IF _account IS NULL THEN

  RETURN QUERY EXECUTE format(
    $query$

    SELECT 
      u.op_type_id, 
      (WITH disc_num AS (
      SELECT DISTINCT block_num FROM hive.operations_view 
      WHERE op_type_id = u.op_type_id
      AND block_num BETWEEN %L AND %L
      GROUP BY block_num
      ORDER BY block_num %s
      LIMIT %L)

    SELECT array_agg(block_num) as block_nums FROM disc_num) AS block_nums
    FROM UNNEST(%L::smallint[]) AS u(op_type_id)
    $query$, 

  _from, _to, 
  _order_is, 
  _limit, 
  _operations) res
  ;

ELSE

  RETURN QUERY EXECUTE format(
    $query$
    WITH source_account_id AS MATERIALIZED (
    SELECT a.id from hive.accounts_view a where a.name = %L)

    SELECT 
      u.op_type_id, 
      (WITH disc_num AS (
        SELECT DISTINCT block_num 
        FROM hive.account_operations_view 
        WHERE op_type_id = u.op_type_id
        AND block_num BETWEEN %L AND %L 
        AND account_id = (SELECT id FROM source_account_id)
        GROUP BY block_num
        ORDER BY block_num %s
        LIMIT %L)
    SELECT array_agg(block_num) as block_nums FROM disc_num) AS block_nums
    FROM UNNEST(%L::smallint[]) AS u(op_type_id)
    $query$, 

  _account,  
  _from, _to, 
  _order_is,  
  _limit,
  _operations)
  ;

END IF;
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_backend.get_block_by_ops_group_by_block_num(_operations INT[], _account TEXT, _order_is hafbe_types.order_is, _from INT, _to INT, _limit INT)
RETURNS SETOF hafbe_types.get_block_by_ops_group_by_block_num
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
IF _account IS NULL THEN

  RETURN QUERY EXECUTE format(
    $query$
    WITH block_num_array AS (
    SELECT 
      u.op_type_id, 
      (WITH disc_num AS (
      SELECT DISTINCT block_num FROM hive.operations_view 
      WHERE op_type_id = u.op_type_id
      AND block_num BETWEEN %L AND %L
      GROUP BY block_num
      ORDER BY block_num %s
      LIMIT %L)

    SELECT array_agg(block_num) as block_nums FROM disc_num) AS block_nums
    FROM UNNEST(%L::smallint[]) AS u(op_type_id)),

    unnest_block_nums AS (
    SELECT op_type_id, unnest(block_nums) AS block_num FROM block_num_array),

    array_op_type_id AS MATERIALIZED (
    SELECT block_num, array_agg(op_type_id) as op_type_id FROM unnest_block_nums
    GROUP BY block_num
    ORDER BY block_num %s)

    SELECT block_num, array(SELECT DISTINCT unnest(op_type_id)) FROM array_op_type_id

    $query$, 

  _from, _to, 
  _order_is, 
  _limit, 
  _operations,
  _order_is) res
  ;

ELSE

  RETURN QUERY EXECUTE format(
    $query$
    WITH source_account_id AS MATERIALIZED (
    SELECT a.id from hive.accounts_view a where a.name = %L),

    block_num_array AS (
    SELECT 
      u.op_type_id, 
      (WITH disc_num AS (
        SELECT DISTINCT block_num 
        FROM hive.account_operations_view 
        WHERE op_type_id = u.op_type_id
        AND block_num BETWEEN %L AND %L 
        AND account_id = (SELECT id FROM source_account_id)
        GROUP BY block_num
        ORDER BY block_num %s
        LIMIT %L)
    SELECT array_agg(block_num) as block_nums FROM disc_num) AS block_nums
    FROM UNNEST(%L::smallint[]) AS u(op_type_id)),

    unnest_block_nums AS (
    SELECT op_type_id, unnest(block_nums) AS block_num FROM block_num_array),

    array_op_type_id AS MATERIALIZED (
    SELECT block_num, array_agg(op_type_id) as op_type_id FROM unnest_block_nums
    GROUP BY block_num
    ORDER BY block_num %s)

    SELECT block_num, array(SELECT DISTINCT unnest(op_type_id)) FROM array_op_type_id
    
    $query$, 

  _account,  
  _from, _to, 
  _order_is,  
  _limit,
  _operations,
  _order_is)
  ;

END IF;
END
$$
;

RESET ROLE;
