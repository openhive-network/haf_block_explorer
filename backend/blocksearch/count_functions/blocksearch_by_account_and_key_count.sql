SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_backend.blocksearch_by_account_and_key_desc_count(
    _operation INT,
    _account TEXT,
    _from INT, 
    _to INT,
    _limit INT,
    _key_content TEXT [],
    _setof_keys JSON
)
RETURNS INT -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
SET plan_cache_mode = force_custom_plan
SET join_collapse_limit = 16
SET from_collapse_limit = 16
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
   WITH get_account_id AS MATERIALIZED
    (
      SELECT 
        av.id 
      FROM hive.accounts_view av 
      WHERE 
        av.name = _account
    ),
    source_ops AS 
    (
      SELECT 
	 	    aov.block_num,
        aov.operation_id
      FROM 
        hive.account_operations_view aov
      WHERE 
        aov.op_type_id = _operation 
        AND aov.account_id = (SELECT id FROM get_account_id)
        AND ((_from IS NULL) OR aov.block_num <= _to)
        AND ((_to IS NULL) OR aov.block_num >= _from)
      ORDER BY aov.block_num DESC 
      LIMIT (_limit * _limit)
    ),
	filter_by_key AS 
    (
      SELECT 
        ov.block_num,
        ov.id
      FROM hive.operations_view ov
      WHERE 
        ov.op_type_id = _operation 
        AND ((_from IS NULL) OR ov.block_num <= _to)
        AND ((_to IS NULL) OR ov.block_num >= _from)
        AND ((_key_content[1] IS NULL) OR jsonb_extract_path_text(ov.body, variadic _path1) = _key_content[1])
        AND ((_key_content[2] IS NULL) OR jsonb_extract_path_text(ov.body, variadic _path2) = _key_content[2]) 
        AND ((_key_content[3] IS NULL) OR jsonb_extract_path_text(ov.body, variadic _path3) = _key_content[3])
      ORDER BY ov.block_num DESC
    ),
    unique_blocks AS (
      SELECT 
        DISTINCT so.block_num
      FROM source_ops so
      JOIN filter_by_key fbk on so.operation_id = fbk.id
    )
    SELECT 
      COUNT(*)
    FROM unique_blocks
  );

END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.blocksearch_by_account_and_key_asc_count(
    _operation INT,
    _account TEXT,
    _from INT, 
    _to INT,
    _limit INT,
    _key_content TEXT [],
    _setof_keys JSON
)
RETURNS INT -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
SET plan_cache_mode = force_custom_plan
SET join_collapse_limit = 16
SET from_collapse_limit = 16
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
   WITH get_account_id AS MATERIALIZED
    (
      SELECT 
        av.id 
      FROM hive.accounts_view av 
      WHERE 
        av.name = _account
    ),
    source_ops AS 
    (
      SELECT 
	 	aov.block_num,
        aov.operation_id
      FROM 
        hive.account_operations_view aov
      WHERE 
        aov.op_type_id = _operation 
        AND aov.account_id = (SELECT id FROM get_account_id)
        AND ((_from IS NULL) OR aov.block_num <= _to)
        AND ((_to IS NULL) OR aov.block_num >= _from)
      ORDER BY aov.block_num ASC 
      LIMIT (_limit * _limit)
    ),
	filter_by_key AS 
    (
      SELECT 
        ov.block_num,
        ov.id
      FROM hive.operations_view ov
      WHERE 
        ov.op_type_id = _operation
        AND ((_from IS NULL) OR ov.block_num <= _to)
        AND ((_to IS NULL) OR ov.block_num >= _from)
        AND ((_key_content[1] IS NULL) OR jsonb_extract_path_text(ov.body, variadic _path1) = _key_content[1])
        AND ((_key_content[2] IS NULL) OR jsonb_extract_path_text(ov.body, variadic _path2) = _key_content[2]) 
        AND ((_key_content[3] IS NULL) OR jsonb_extract_path_text(ov.body, variadic _path3) = _key_content[3])
      ORDER BY ov.block_num ASC
    ),
    unique_blocks AS (
      SELECT 
        DISTINCT so.block_num
      FROM source_ops so
      JOIN filter_by_key fbk on so.operation_id = fbk.id
    )
    SELECT 
      COUNT(*)
    FROM unique_blocks
  );

END
$$;

RESET ROLE;
