SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_backend.blocksearch_by_key_desc(
    _operation INT,
    _from INT, 
    _to INT,
    _page INT,
    _limit INT,
    _key_content TEXT [],
    _setof_keys JSON
)
RETURNS JSONB -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
SET plan_cache_mode = force_custom_plan
SET JIT = OFF
AS
$$
DECLARE
  _count INT;
  _total_pages INT;
  _rest_of_division INT;

  _result JSONB;
  _offset INT := (((_page - 1) * _limit));
  -- keys must be declared in seperate variables
  -- otherwise planner will not use indexes
  _path1 TEXT[] := ARRAY(SELECT json_array_elements_text(_setof_keys->0));
  _path2 TEXT[] := ARRAY(SELECT json_array_elements_text(_setof_keys->1));
  _path3 TEXT[] := ARRAY(SELECT json_array_elements_text(_setof_keys->2));
BEGIN  
  _count := hafbe_backend.blocksearch_by_key_desc_count(_operation, _from, _to, _limit, _key_content, _setof_keys);

  _total_pages := (
    CASE 
      WHEN (_count % _limit) = 0 THEN 
        _count / _limit 
      ELSE ((_count / _limit) + 1) 
      END
  )::INT;

  IF _total_pages = 0 THEN
    RETURN json_build_object(
    'total_blocks', _count,
    'total_pages', _total_pages,
    'blocks_result', '[]'::jsonb
    );
  END IF;

  IF _page > _total_pages AND _total_pages != 0 THEN
    RAISE EXCEPTION 'Page number exceeds total pages';
  END IF;
  
  _rest_of_division := (_count % _limit)::INT;

  SELECT jsonb_agg(result) INTO _result
  FROM (
	  WITH block_range AS 
		(
      SELECT 
        ov.block_num,
        ov.op_type_id
      FROM hive.operations_view ov
      WHERE 
        ov.op_type_id = _operation
        AND ((_from IS NULL) OR ov.block_num >= _from)
        AND ((_to IS NULL)   OR ov.block_num <= _to) 
        AND ((_key_content[1] IS NULL) OR jsonb_extract_path_text(ov.body, variadic _path1) = _key_content[1])
        AND ((_key_content[2] IS NULL) OR jsonb_extract_path_text(ov.body, variadic _path2) = _key_content[2]) 
        AND ((_key_content[3] IS NULL) OR jsonb_extract_path_text(ov.body, variadic _path3) = _key_content[3])	
    )
    SELECT 
      ov.block_num,
      array_agg(DISTINCT ov.op_type_id) AS op_type_ids
    FROM block_range ov
    GROUP BY ov.block_num
    ORDER BY ov.block_num DESC
    OFFSET _offset
    LIMIT (CASE WHEN _page = _total_pages AND _rest_of_division != 0 THEN _rest_of_division ELSE _limit END)
  ) AS result;

  RETURN json_build_object(
    'total_blocks', _count,
    'total_pages', _total_pages,
    'blocks_result', COALESCE(_result, '[]'::jsonb)
  );

END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.blocksearch_by_key_asc(
    _operation INT,
    _from INT, 
    _to INT,
    _page INT,
    _limit INT,
    _key_content TEXT [],
    _setof_keys JSON
)
RETURNS JSONB -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
SET plan_cache_mode = force_custom_plan
SET JIT = OFF
AS
$$
DECLARE
  _count INT;
  _total_pages INT;
  _rest_of_division INT;

  _result JSONB;
  _offset INT := (((_page - 1) * _limit));
  -- keys must be declared in seperate variables
  -- otherwise planner will not use indexes
  _path1 TEXT[] := ARRAY(SELECT json_array_elements_text(_setof_keys->0));
  _path2 TEXT[] := ARRAY(SELECT json_array_elements_text(_setof_keys->1));
  _path3 TEXT[] := ARRAY(SELECT json_array_elements_text(_setof_keys->2));
BEGIN  
  _count := hafbe_backend.blocksearch_by_key_asc_count(_operation, _from, _to, _limit, _key_content, _setof_keys);

  _total_pages := (
    CASE 
      WHEN (_count % _limit) = 0 THEN 
        _count / _limit 
      ELSE ((_count / _limit) + 1) 
      END
  )::INT;

  IF _total_pages = 0 THEN
    RETURN json_build_object(
    'total_blocks', _count,
    'total_pages', _total_pages,
    'blocks_result', '[]'::jsonb
    );
  END IF;

  IF _page > _total_pages AND _total_pages != 0 THEN
    RAISE EXCEPTION 'Page number exceeds total pages';
  END IF;
  
  _rest_of_division := (_count % _limit)::INT;

  SELECT jsonb_agg(result) INTO _result
  FROM (
	  WITH block_range AS 
		(
      SELECT 
        ov.block_num,
        ov.op_type_id
      FROM hive.operations_view ov
      WHERE 
        ov.op_type_id = _operation
        AND ((_from IS NULL) OR ov.block_num >= _from)
        AND ((_to IS NULL)   OR ov.block_num <= _to) 
        AND ((_key_content[1] IS NULL) OR jsonb_extract_path_text(ov.body, variadic _path1) = _key_content[1])
        AND ((_key_content[2] IS NULL) OR jsonb_extract_path_text(ov.body, variadic _path2) = _key_content[2]) 
        AND ((_key_content[3] IS NULL) OR jsonb_extract_path_text(ov.body, variadic _path3) = _key_content[3])	
    )
    SELECT 
      ov.block_num,
      array_agg(DISTINCT ov.op_type_id) AS op_type_ids
    FROM block_range ov
    GROUP BY ov.block_num
    ORDER BY ov.block_num ASC
    OFFSET _offset
    LIMIT (CASE WHEN _page = _total_pages AND _rest_of_division != 0 THEN _rest_of_division ELSE _limit END)
  ) AS result;

  RETURN json_build_object(
    'total_blocks', _count,
    'total_pages', _total_pages,
    'blocks_result', COALESCE(_result, '[]'::jsonb)
  );

END
$$;

RESET ROLE;
