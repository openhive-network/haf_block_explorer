SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_backend.blocksearch_by_block_desc(
    _operations INT[],
    _from INT, 
    _to INT,
    _page INT,
    _limit INT
)
RETURNS JSONB -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
--plan is more stable with force_custom_plan
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
BEGIN
  _count := hafbe_backend.blocksearch_desc_count(_operations, _from, _to, _limit);

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
    WITH ops_list AS MATERIALIZED
    (
      SELECT 
        array_agg(ot.id) AS op_type_ids
      FROM hafd.operation_types ot
      WHERE 
        ((_operations IS NULL) OR ot.id = ANY(_operations))
    ),
	block_range AS 
	(
    SELECT 
        ov.block_num,
        ov.op_type_id
    FROM hive.operations_view ov
    WHERE 
        ov.op_type_id = ANY((SELECT op_type_ids FROM ops_list)::SMALLINT[])
    --  ov.op_type_id IN (SELECT unnest(op_type_ids) FROM ops_list) - this is slower
        AND ((_to IS NULL) OR ov.block_num <= _to)
        AND ((_from IS NULL) OR ov.block_num >= _from)
	  ORDER BY ov.block_num DESC
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

CREATE OR REPLACE FUNCTION hafbe_backend.blocksearch_by_block_asc(
    _operations INT[],
    _from INT, 
    _to INT,
    _page INT,
    _limit INT
)
RETURNS JSONB -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
--plan is more stable with force_custom_plan
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
BEGIN
  _count := hafbe_backend.blocksearch_asc_count(_operations, _from, _to, _limit);

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
    WITH ops_list AS MATERIALIZED
    (
      SELECT 
        array_agg(ot.id) AS op_type_ids
      FROM hafd.operation_types ot
      WHERE 
        ((_operations IS NULL) OR ot.id = ANY(_operations))
    ),
	block_range AS 
	(
    SELECT 
        ov.block_num,
        ov.op_type_id
    FROM hive.operations_view ov
    WHERE 
        ov.op_type_id = ANY((SELECT op_type_ids FROM ops_list)::SMALLINT[])
    --  ov.op_type_id IN (SELECT unnest(op_type_ids) FROM ops_list) - this is slower
        AND ((_to IS NULL) OR ov.block_num <= _to)
        AND ((_from IS NULL) OR ov.block_num >= _from)
	  ORDER BY ov.block_num ASC
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
