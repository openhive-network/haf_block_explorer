SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_backend.blocksearch_by_key_desc_count(
    _operation INT,
    _from INT, 
    _to INT,
    _limit INT,
    _key_content TEXT [],
    _setof_keys JSON
)
RETURNS INT -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
SET plan_cache_mode = force_custom_plan
SET JIT = OFF
AS
$$
DECLARE
  -- keys must be declared in seperate variables
  -- otherwise planner will not use indexes
  _path1 TEXT[] := ARRAY(SELECT json_array_elements_text(_setof_keys->0));
  _path2 TEXT[] := ARRAY(SELECT json_array_elements_text(_setof_keys->1));
  _path3 TEXT[] := ARRAY(SELECT json_array_elements_text(_setof_keys->2));
BEGIN
  RETURN (
    WITH blocks AS (
      SELECT 
        ov.block_num
      FROM hive.operations_view ov
      WHERE 
        ov.op_type_id = _operation
        AND ((_to IS NULL) OR ov.block_num <= _to)
        AND ((_from IS NULL) OR ov.block_num >= _from)
        AND ((_key_content[1] IS NULL) OR jsonb_extract_path_text(ov.body, variadic _path1) = _key_content[1])
        AND ((_key_content[2] IS NULL) OR jsonb_extract_path_text(ov.body, variadic _path2) = _key_content[2]) 
        AND ((_key_content[3] IS NULL) OR jsonb_extract_path_text(ov.body, variadic _path3) = _key_content[3])
      LIMIT (_limit * _limit)
    ),
    unique_blocks AS (
      SELECT 
        DISTINCT ov.block_num
      FROM blocks ov
    )
    SELECT 
      COUNT(*)
    FROM unique_blocks
  );
END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.blocksearch_by_key_asc_count(
    _operation INT,
    _from INT, 
    _to INT,
    _limit INT,
    _key_content TEXT [],
    _setof_keys JSON
)
RETURNS INT -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
SET plan_cache_mode = force_custom_plan
SET JIT = OFF
AS
$$
BEGIN
  RETURN (
    WITH blocks AS (
      SELECT 
        ov.block_num
      FROM hive.operations_view ov
      WHERE 
        ov.op_type_id = _operation
        AND ((_to IS NULL) OR ov.block_num <= _to)
        AND ((_from IS NULL) OR ov.block_num >= _from)
        AND ((_key_content[1] IS NULL) OR jsonb_extract_path_text(ov.body, variadic ARRAY(SELECT json_array_elements_text(_setof_keys->0))) = _key_content[1])  
        AND ((_key_content[2] IS NULL) OR jsonb_extract_path_text(ov.body, variadic ARRAY(SELECT json_array_elements_text(_setof_keys->1))) = _key_content[2]) 
        AND ((_key_content[3] IS NULL) OR jsonb_extract_path_text(ov.body, variadic ARRAY(SELECT json_array_elements_text(_setof_keys->2))) = _key_content[3])
      ORDER BY ov.block_num ASC
      LIMIT (_limit * _limit)
    ),
    unique_blocks AS (
      SELECT 
        DISTINCT ov.block_num
      FROM blocks ov
    )
    SELECT 
      COUNT(*)
    FROM unique_blocks
  );
END
$$;

RESET ROLE;
