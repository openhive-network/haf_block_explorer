SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_backend.blocksearch_desc_count(
    _operations INT[],
    _from INT, 
    _to INT,
    _limit INT
)
RETURNS INT -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
SET plan_cache_mode = force_custom_plan
SET JIT = OFF
AS
$$
BEGIN
  RETURN (
    WITH ops_list AS MATERIALIZED
    (
      SELECT 
        array_agg(ot.id) AS op_type_ids
      FROM hafd.operation_types ot
      WHERE 
        ((_operations IS NULL) OR ot.id = ANY(_operations))
    ),
    blocks AS (
      SELECT 
        ov.block_num
      FROM hive.operations_view ov
      WHERE 
        ov.op_type_id = ANY((SELECT op_type_ids FROM ops_list)::SMALLINT[]) 
        AND ((_from IS NULL) OR ov.block_num <= _to) 
        AND ((_to IS NULL) OR ov.block_num >= _from)
      ORDER BY ov.block_num DESC
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

CREATE OR REPLACE FUNCTION hafbe_backend.blocksearch_asc_count(
    _operations INT[],
    _from INT, 
    _to INT,
    _limit INT
)
RETURNS INT -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
SET plan_cache_mode = force_custom_plan
SET JIT = OFF
AS
$$
BEGIN
  RETURN (
    WITH ops_list AS MATERIALIZED
    (
      SELECT 
        array_agg(ot.id) AS op_type_ids
      FROM hafd.operation_types ot
      WHERE 
        ((_operations IS NULL) OR ot.id = ANY(_operations))
    ),
    blocks AS (
      SELECT 
        ov.block_num
      FROM hive.operations_view ov
      WHERE 
        ov.op_type_id = ANY((SELECT op_type_ids FROM ops_list)::SMALLINT[])
        AND ((_from IS NULL) OR ov.block_num <= _to)
        AND ((_to IS NULL) OR ov.block_num >= _from)
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
