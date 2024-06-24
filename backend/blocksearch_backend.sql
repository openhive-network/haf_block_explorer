SET ROLE hafbe_owner;
-- Functions used in hafbe_endpoints.get_block_by_op
CREATE OR REPLACE FUNCTION hafbe_backend.get_block_by_single_op(
    _operations int,
    _account text,
    _order_is hafbe_types.sort_direction, -- noqa: LT01, CP05
    _from int, _to int,
    _limit int,
    _key_content text [],
    _setof_keys json
)
RETURNS SETOF hafbe_types.block_by_ops -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
AS
$$
DECLARE
  _first_key BOOLEAN = (_key_content[1] IS NULL);
  _second_key BOOLEAN = (_key_content[2] IS NULL);
  _third_key BOOLEAN = (_key_content[3] IS NULL);
BEGIN
IF _account IS NULL THEN
  RETURN QUERY EXECUTE format(

    $query$
    WITH operation_range AS (
    SELECT DISTINCT ov.block_num FROM hive.operations_view ov
    WHERE 
      ov.op_type_id = %L AND 
      ov.block_num BETWEEN %L AND %L AND 
      (%L OR jsonb_extract_path_text(ov.body, variadic %L) = %L) AND 
      (%L OR jsonb_extract_path_text(ov.body, variadic %L) = %L) AND 
      (%L OR jsonb_extract_path_text(ov.body, variadic %L) = %L)
    ORDER BY ov.block_num %s
    LIMIT %L)
    
    SELECT opr.block_num, ARRAY(SELECT %L::INT) FROM operation_range opr
    ORDER BY opr.block_num %s
    $query$, 

  _operations,
  _from, _to, 
  _first_key,
  ARRAY(SELECT json_array_elements_text(_setof_keys->0)), _key_content[1],
  _second_key,
  ARRAY(SELECT json_array_elements_text(_setof_keys->1)), _key_content[2], 
  _third_key,
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
      ov.op_type_id = %L AND
      (%L OR jsonb_extract_path_text(ov.body, variadic %L) = %L) AND 
      (%L OR jsonb_extract_path_text(ov.body, variadic %L) = %L) AND 
      (%L OR jsonb_extract_path_text(ov.body, variadic %L) = %L)
      ORDER BY ov.block_num %s
      LIMIT %L)

      SELECT opr.block_num, ARRAY(SELECT %L::INT) FROM operation_range opr
      ORDER BY opr.block_num %s
      $query$, 

    _account, 
    _operations, 
    _from, _to, 
    _order_is, 
    _operations, 
    _first_key,
    ARRAY(SELECT json_array_elements_text(_setof_keys->0)), _key_content[1],
    _second_key,
    ARRAY(SELECT json_array_elements_text(_setof_keys->1)), _key_content[2],
    _third_key,
    ARRAY(SELECT json_array_elements_text(_setof_keys->2)), _key_content[3],
    _order_is, 
    _limit,
    _operations,
    _order_is)
    ;

END IF;
END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.get_block_by_ops_group_by_block_num(
    _operations int [],
    _account text,
    _order_is hafbe_types.sort_direction, -- noqa: LT01, CP05
    _from int,
    _to int,
    _limit int
)
RETURNS SETOF hafbe_types.block_by_ops -- noqa: LT01, CP05
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
    FROM UNNEST(%L::INT[]) AS unnested_op_types(op_type_id)),

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
    FROM UNNEST(%L::INT[]) AS unnested_op_types(op_type_id)),

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

-- used in comment history endpoint
CREATE OR REPLACE FUNCTION hafbe_backend.get_comment_operations(
    _author text,
    _permlink text,
    _page_num int,
    _page_size int,
    _operation_types int [],
    _from int,
    _to int,
    _body_limit int
)
RETURNS SETOF hafbe_types.comment_history -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
SET enable_hashjoin = OFF
AS
$$
DECLARE
  _offset INT := (_page_num - 1) * _page_size;
  _second_key BOOLEAN = (_permlink IS NULL);
BEGIN
  RETURN QUERY
  WITH operation_range AS MATERIALIZED (
  SELECT 
    ov.body_binary::jsonb->'value'->>'permlink' as permlink,
    ov.body_binary::jsonb->'value'->>'author' as author,
    ov.block_num, ov.id, ov.body_binary::jsonb as body, ov.trx_in_block
  FROM hive.operations_view ov
  WHERE 
    ov.block_num BETWEEN _from AND _to AND
    ov.op_type_id = ANY(_operation_types) AND 
    ov.body_binary::jsonb->'value'->>'author' = _author AND
    (_second_key OR ov.body_binary::jsonb->'value'->>'permlink' = _permlink)
  ORDER BY author, permlink, ov.id
  LIMIT _page_size
  OFFSET _offset),
  add_transactions AS MATERIALIZED
  (
    SELECT 
      orr.permlink, 
      orr.author, 
      orr.block_num, 
      orr.id, 
      orr.body, 
      encode(htv.trx_hash, 'hex') AS trx_hash
    FROM operation_range orr
    LEFT JOIN hive.transactions_view htv ON htv.block_num = orr.block_num AND htv.trx_in_block = orr.trx_in_block
  )
-- filter too long operation bodies 
  SELECT filtered_operations.permlink, filtered_operations.block_num, filtered_operations.id, filtered_operations.timestamp, filtered_operations.trx_hash,  (filtered_operations.composite).body, (filtered_operations.composite).is_modified
  FROM (
  SELECT hafbe_backend.operation_body_filter(opr.body, opr.id, _body_limit) as composite, opr.id, opr.block_num, opr.permlink, opr.author, hb.created_at timestamp, opr.trx_hash
  FROM add_transactions opr
  JOIN hive.blocks_view hb ON hb.num = opr.block_num
  ) filtered_operations
  ORDER BY filtered_operations.author, filtered_operations.permlink, filtered_operations.id;

END
$$;

-- used in comment history endpoint
CREATE OR REPLACE FUNCTION hafbe_backend.get_comment_operations_count(
    _author text,
    _permlink text,
    _operation_types int [],
    _from int,
    _to int
)
RETURNS BIGINT -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE 
SET enable_hashjoin = OFF
AS
$$
DECLARE
  _second_key BOOLEAN = (_permlink IS NULL);
BEGIN
  RETURN (
  SELECT COUNT(*) as count
  FROM hive.operations_view ov
  WHERE 
    ov.block_num BETWEEN _from AND _to AND 
    ov.op_type_id = ANY(_operation_types) AND 
    ov.body_binary::jsonb->'value'->>'author' = _author AND
    (_second_key OR ov.body_binary::jsonb->'value'->>'permlink' = _permlink)
  );

END
$$;


RESET ROLE;
