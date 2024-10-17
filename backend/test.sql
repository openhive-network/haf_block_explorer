CREATE OR REPLACE FUNCTION hafbe_backend.bs_operations(
    _operations INT[],
    _order_is hafbe_types.sort_direction, -- noqa: LT01, CP05
    _from INT,
    _to INT,
    _page INT,
    _page_size INT,
    _key_content TEXT [],
    _setof_keys JSON
)
RETURNS JSON -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
AS
$$
DECLARE
  _operation_filter_not_exists BOOLEAN := (_operations IS NULL);
  _offset INT := (((_page - 1) * _page_size) + 1);
BEGIN
  RETURN (
    WITH ops_list AS MATERIALIZED
    (
      SELECT 
        ot.id AS op_type_id
      FROM hive.operation_types ot
      WHERE 
        (_operation_filter_not_exists OR ot.id = ANY(_operations))
    ),
    block_num_array AS 
    (
      SELECT 
        ot.op_type_id, 
        hafbe_backend.array_blocksearch_blocks(
          ot.op_type_id,
          _order_is,
          _from,
          _to,
          _page_size,
          _key_content,
          _setof_keys
        ) AS block_nums
      FROM ops_list ot
    ),
    unnest_block_nums AS MATERIALIZED
    (
      SELECT 
        bna.op_type_id, 
        unnest(bna.block_nums) AS block_num 
      FROM block_num_array bna
    ),
    array_op_type_id AS  
    (
      SELECT 
        ubn.block_num, 
        array_agg(ubn.op_type_id) AS op_type_id 
      FROM unnest_block_nums ubn
      GROUP BY ubn.block_num
    ),
    count_blocks AS MATERIALIZED
    (
      SELECT 
        COUNT(*) AS blocks_count
      FROM array_op_type_id bna
    ),
    count_pages AS
    (
      SELECT (
        CASE WHEN (blocks_count % _page_size) = 0 THEN 
          blocks_count/_page_size 
        ELSE ((blocks_count/_page_size) + 1) 
        END
      )::INT AS page_count
      FROM count_blocks
    )
    SELECT json_build_object(
      'total_blocks', (SELECT blocks_count 
          FROM count_blocks
          ),
      'total_pages', (SELECT page_count 
          FROM count_pages
          ),
      'blocks_result', 
        COALESCE((SELECT to_json(array_agg(row)) FROM (
          SELECT 
            block_num, 
            ARRAY(
              SELECT 
                DISTINCT unnest(op_type_id)
            ) AS op_type_ids
          FROM array_op_type_id
          ORDER BY
            (CASE WHEN _order_is = 'desc' THEN block_num ELSE NULL END) DESC,
            (CASE WHEN _order_is = 'asc' THEN block_num ELSE NULL END) ASC
          OFFSET _offset
          LIMIT _page_size
      ) row),'[]')
    )
  );
END
$$;



CREATE OR REPLACE FUNCTION hafbe_backend.bs_accounts(
    _operations INT[],
    _account TEXT,
    _order_is hafbe_types.sort_direction, -- noqa: LT01, CP05
    _from INT,
    _to INT,
    _page INT,
    _page_size INT,
    _key_content TEXT [],
    _setof_keys JSON
)
RETURNS JSON -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
AS
$$
DECLARE
  _operation_filter_not_exists BOOLEAN := (_operations IS NULL);
  _offset INT := (((_page - 1) * _page_size) + 1);
BEGIN
  RETURN (
    WITH ops_list AS MATERIALIZED
    (
      SELECT 
        ot.id AS op_type_id
      FROM hive.operation_types ot
      WHERE 
        (_operation_filter_not_exists OR ot.id = ANY(_operations))
    ),
    source_account_id AS MATERIALIZED 
    (
      SELECT 
        av.id
      FROM hive.accounts_view av 
      WHERE av.name = _account
    )
    block_num_array AS 
    (
      SELECT 
        ot.op_type_id, 
        hafbe_backend.array_blocksearch_blocks_by_account(
          ot.op_type_id,
          _order_is,
          _from,
          _to,
          _page_size,
          _key_content,
          _setof_keys
        ) AS block_nums
      FROM 
        ops_list ot,
        source_account_id sai
    ),
    unnest_block_nums AS MATERIALIZED
    (
      SELECT 
        bna.op_type_id, 
        unnest(bna.block_nums) AS block_num 
      FROM block_num_array bna
    ),
    array_op_type_id AS  
    (
      SELECT 
        ubn.block_num, 
        array_agg(ubn.op_type_id) AS op_type_id 
      FROM unnest_block_nums ubn
      GROUP BY ubn.block_num
    ),
    count_blocks AS MATERIALIZED
    (
      SELECT 
        COUNT(*) AS blocks_count
      FROM array_op_type_id bna
    ),
    count_pages AS
    (
      SELECT (
        CASE WHEN (blocks_count % _page_size) = 0 THEN 
          blocks_count/_page_size 
        ELSE ((blocks_count/_page_size) + 1) 
        END
      )::INT AS page_count
      FROM count_blocks
    )
    SELECT json_build_object(
      'total_blocks', (SELECT blocks_count 
          FROM count_blocks
          ),
      'total_pages', (SELECT page_count 
          FROM count_pages
          ),
      'blocks_result', 
        COALESCE((SELECT to_json(array_agg(row)) FROM (
          SELECT 
            block_num, 
            ARRAY(
              SELECT 
                DISTINCT unnest(op_type_id)
            ) AS op_type_ids
          FROM array_op_type_id
          ORDER BY
            (CASE WHEN _order_is = 'desc' THEN block_num ELSE NULL END) DESC,
            (CASE WHEN _order_is = 'asc' THEN block_num ELSE NULL END) ASC
          OFFSET _offset
          LIMIT _page_size
      ) row),'[]')
    )
  );
BEGIN
END
$$;



CREATE OR REPLACE FUNCTION hafbe_backend.array_blocksearch_blocks_by_account(
    _operation int,
    _order_is hafbe_types.sort_direction, -- noqa: LT01, CP05
    _from int, 
    _to int,
    _limit int,
    _key_content text [],
    _setof_keys json
)
RETURNS INT[] -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
AS
$$
DECLARE
  __no_start_date BOOLEAN := (_from IS NULL);
  __no_end_date BOOLEAN := (_to IS NULL);
  _first_key BOOLEAN = (_key_content[1] IS NULL);
  _second_key BOOLEAN = (_key_content[2] IS NULL);
  _third_key BOOLEAN = (_key_content[3] IS NULL);
BEGIN


      source_ops AS (
      SELECT array_agg(aov.operation_id) AS operation_id, aov.block_num
      FROM hive.account_operations_view aov
      WHERE 
        aov.op_type_id = %L AND 
        aov.account_id = (SELECT id FROM source_account_id) AND 
        (%L OR aov.block_num >= %L) AND
	      (%L OR aov.block_num <= %L)
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


IF _order_is = 'desc' THEN
  RETURN (
    WITH disc_num AS 
    (
      SELECT 
        DISTINCT ov.block_num 
      FROM hive.operations_view ov
      WHERE 
        ov.op_type_id = _operation AND
        (__no_start_date OR ov.block_num >= _from) AND
        (__no_end_date OR ov.block_num <= _to) AND
        (_first_key OR jsonb_extract_path_text(ov.body, variadic ARRAY(SELECT json_array_elements_text(_setof_keys->0))) = _key_content[1]) AND 
        (_second_key OR jsonb_extract_path_text(ov.body, variadic ARRAY(SELECT json_array_elements_text(_setof_keys->1))) = _key_content[2]) AND 
        (_third_key OR jsonb_extract_path_text(ov.body, variadic ARRAY(SELECT json_array_elements_text(_setof_keys->2))) = _key_content[3])
      ORDER BY ov.block_num DESC
      LIMIT _limit
    )
    SELECT 
      array_agg(block_num)
    FROM disc_num
  );
ELSE
  RETURN (
    WITH disc_num AS 
    (
      SELECT 
        DISTINCT ov.block_num 
      FROM hive.operations_view ov
      WHERE 
        ov.op_type_id = _operation AND
        (__no_start_date OR ov.block_num >= _from) AND
        (__no_end_date OR ov.block_num <= _to) AND
        (_first_key OR jsonb_extract_path_text(ov.body, variadic ARRAY(SELECT json_array_elements_text(_setof_keys->0))) = _key_content[1]) AND 
        (_second_key OR jsonb_extract_path_text(ov.body, variadic ARRAY(SELECT json_array_elements_text(_setof_keys->1))) = _key_content[2]) AND 
        (_third_key OR jsonb_extract_path_text(ov.body, variadic ARRAY(SELECT json_array_elements_text(_setof_keys->2))) = _key_content[3])
      ORDER BY ov.block_num ASC
      LIMIT _limit
    )
    SELECT 
      array_agg(block_num)
    FROM disc_num
  );
END IF
END
$$;



CREATE OR REPLACE FUNCTION hafbe_backend.array_blocksearch_blocks(
    _operation int,
    _order_is hafbe_types.sort_direction, -- noqa: LT01, CP05
    _from int, 
    _to int,
    _limit int,
    _key_content text [],
    _setof_keys json
)
RETURNS INT[] -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
AS
$$
DECLARE
  __no_start_date BOOLEAN := (_from IS NULL);
  __no_end_date BOOLEAN := (_to IS NULL);
  _first_key BOOLEAN = (_key_content[1] IS NULL);
  _second_key BOOLEAN = (_key_content[2] IS NULL);
  _third_key BOOLEAN = (_key_content[3] IS NULL);
BEGIN
IF _order_is = 'desc' THEN
  RETURN (
    WITH disc_num AS 
    (
      SELECT 
        DISTINCT ov.block_num 
      FROM hive.operations_view ov
      WHERE 
        ov.op_type_id = _operation AND
        (__no_start_date OR ov.block_num >= _from) AND
        (__no_end_date OR ov.block_num <= _to) AND
        (_first_key OR jsonb_extract_path_text(ov.body, variadic ARRAY(SELECT json_array_elements_text(_setof_keys->0))) = _key_content[1]) AND 
        (_second_key OR jsonb_extract_path_text(ov.body, variadic ARRAY(SELECT json_array_elements_text(_setof_keys->1))) = _key_content[2]) AND 
        (_third_key OR jsonb_extract_path_text(ov.body, variadic ARRAY(SELECT json_array_elements_text(_setof_keys->2))) = _key_content[3])
      ORDER BY ov.block_num DESC
      LIMIT _limit
    )
    SELECT 
      array_agg(block_num)
    FROM disc_num
  );
ELSE
  RETURN (
    WITH disc_num AS 
    (
      SELECT 
        DISTINCT ov.block_num 
      FROM hive.operations_view ov
      WHERE 
        ov.op_type_id = _operation AND
        (__no_start_date OR ov.block_num >= _from) AND
        (__no_end_date OR ov.block_num <= _to) AND
        (_first_key OR jsonb_extract_path_text(ov.body, variadic ARRAY(SELECT json_array_elements_text(_setof_keys->0))) = _key_content[1]) AND 
        (_second_key OR jsonb_extract_path_text(ov.body, variadic ARRAY(SELECT json_array_elements_text(_setof_keys->1))) = _key_content[2]) AND 
        (_third_key OR jsonb_extract_path_text(ov.body, variadic ARRAY(SELECT json_array_elements_text(_setof_keys->2))) = _key_content[3])
      ORDER BY ov.block_num ASC
      LIMIT _limit
    )
    SELECT 
      array_agg(block_num)
    FROM disc_num
  );
END IF
END
$$;
