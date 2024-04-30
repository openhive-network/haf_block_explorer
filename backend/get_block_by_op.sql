-- Functions used in hafbe_endpoints.get_block_by_op

SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_backend.get_block_by_single_op(
    _operations INT,
    _account TEXT,
    _order_is hafbe_types.order_is, -- noqa: LT01, CP05
    _from INT, _to INT,
    _limit INT,
    _key_content TEXT [],
    _setof_keys JSON
)
RETURNS SETOF hafbe_types.get_block_by_ops -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
IF _account IS NULL THEN
  RETURN QUERY EXECUTE format(

    $query$
    WITH operation_range AS (
    SELECT DISTINCT ov.block_num FROM hive.operations_view ov
    WHERE 
      ov.op_type_id = %L
      AND ov.block_num BETWEEN %L AND %L 
      AND (CASE WHEN %L IS NOT NULL THEN
      jsonb_extract_path_text(ov.body, variadic %L) = %L ELSE
      TRUE
      END)
      AND (CASE WHEN %L IS NOT NULL THEN
      jsonb_extract_path_text(ov.body, variadic %L) = %L ELSE
      TRUE
      END)
      AND (CASE WHEN %L IS NOT NULL THEN
      jsonb_extract_path_text(ov.body, variadic %L) = %L ELSE
      TRUE
      END)
    ORDER BY ov.block_num %s
    LIMIT %L)
    
    SELECT opr.block_num, ARRAY(SELECT %L::smallint) FROM operation_range opr
    ORDER BY opr.block_num %s
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
  _limit,
  _operations,
  _order_is) res
  ;

ELSE

  RETURN QUERY EXECUTE format(
      $query$
      WITH source_account_id AS MATERIALIZED (
      SELECT av.id from hive.accounts_view av where av.name = %L),

      source_ops AS (
      SELECT array_agg(aov.operation_id) AS operation_id, aov.block_num
      FROM hive.account_operations_view aov
      WHERE 
        aov.op_type_id = %L AND 
        aov.account_id = (SELECT id FROM source_account_id) AND 
        aov.block_num BETWEEN %L AND %L
      GROUP BY aov.block_num
      ORDER BY aov.block_num %s),  

      unnest_ops AS MATERIALIZED (
      SELECT unnest(operation_id) AS operation_id
      FROM source_ops),

      operation_range AS (
      SELECT DISTINCT ov.block_num
      FROM hive.operations_view ov
      JOIN unnest_ops s on s.operation_id = ov.id
      WHERE 
        (CASE WHEN %L IS NOT NULL THEN
        jsonb_extract_path_text(ov.body, variadic %L) = %L ELSE
        TRUE
        END) AND
        (CASE WHEN %L IS NOT NULL THEN
        jsonb_extract_path_text(ov.body, variadic %L) = %L ELSE
        TRUE
        END) AND
        (CASE WHEN %L IS NOT NULL THEN
        jsonb_extract_path_text(ov.body, variadic %L) = %L ELSE
        TRUE
        END) AND
        ov.op_type_id = %L
      ORDER BY ov.block_num %s
      LIMIT %L)

      SELECT opr.block_num, ARRAY(SELECT %L::smallint) FROM operation_range opr
      ORDER BY opr.block_num %s
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
    _limit,
    _operations,
    _order_is)
    ;

END IF;
END
$$;


CREATE OR REPLACE FUNCTION hafbe_backend.get_block_by_ops_group_by_block_num(
    _operations INT [],
    _account TEXT,
    _order_is hafbe_types.order_is, -- noqa: LT01, CP05
    _from INT,
    _to INT,
    _limit INT
)
RETURNS SETOF hafbe_types.get_block_by_ops -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
IF _account IS NULL THEN

  RETURN QUERY EXECUTE format(
    $query$
    WITH block_num_array AS (
    SELECT unnested_op_types.op_type_id, 
    (
      WITH disc_num AS (
      SELECT DISTINCT ov.block_num 
      FROM hive.operations_view ov
      WHERE ov.op_type_id = unnested_op_types.op_type_id
      AND ov.block_num BETWEEN %L AND %L
      GROUP BY ov.block_num
      ORDER BY ov.block_num %s
      LIMIT %L)
      SELECT array_agg(dn.block_num) as block_nums
      FROM disc_num dn
    ) AS block_nums
    FROM UNNEST(%L::smallint[]) AS unnested_op_types(op_type_id)),

    unnest_block_nums AS (
    SELECT bna.op_type_id, unnest(bna.block_nums) AS block_num 
    FROM block_num_array bna),

    array_op_type_id AS MATERIALIZED (
    SELECT ubn.block_num, array_agg(ubn.op_type_id) as op_type_id 
    FROM unnest_block_nums ubn
    GROUP BY ubn.block_num
    ORDER BY ubn.block_num %s)

    SELECT aoti.block_num, array(SELECT DISTINCT unnest(aoti.op_type_id)) 
    FROM array_op_type_id aoti

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
    SELECT av.id from hive.accounts_view av where av.name = %L),

    block_num_array AS (
    SELECT unnested_op_types.op_type_id, 
    (
      WITH disc_num AS (
      SELECT DISTINCT aov.block_num 
      FROM hive.account_operations_view aov
      WHERE aov.op_type_id = unnested_op_types.op_type_id
      AND aov.block_num BETWEEN %L AND %L 
      AND aov.account_id = (SELECT id FROM source_account_id)
      GROUP BY aov.block_num
      ORDER BY aov.block_num %s
      LIMIT %L)
      SELECT array_agg(block_num) as block_nums FROM disc_num
    ) AS block_nums
    FROM UNNEST(%L::smallint[]) AS unnested_op_types(op_type_id)),

    unnest_block_nums AS (
    SELECT bna.op_type_id, unnest(bna.block_nums) AS block_num 
    FROM block_num_array bna),

    array_op_type_id AS MATERIALIZED (
    SELECT ubn.block_num, array_agg(ubn.op_type_id) as op_type_id
    FROM unnest_block_nums ubn
    GROUP BY ubn.block_num
    ORDER BY ubn.block_num %s)

    SELECT aoti.block_num, array(SELECT DISTINCT unnest(aoti.op_type_id)) 
    FROM array_op_type_id aoti
    
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
$$;

RESET ROLE;
