SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_backend.blocksearch_by_account_desc_count(
    _operations INT[],
    _account TEXT,
    _from INT, 
    _to INT,
    _limit INT
)
RETURNS INT -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
SET plan_cache_mode = force_generic_plan
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
    get_account_id AS MATERIALIZED
    (
      SELECT 
        av.id 
      FROM hive.accounts_view av 
      WHERE 
        av.name = _account
    ),
    blocks AS 
    (
      SELECT 
          aov.block_num
      FROM hive.account_operations_view aov
      WHERE 
        aov.op_type_id = ANY((SELECT op_type_ids FROM ops_list)::SMALLINT[])
        AND aov.account_id = (SELECT id FROM get_account_id)
        AND ((_to IS NULL) OR aov.block_num <= _to)
        AND ((_from IS NULL) OR aov.block_num >= _from)
      ORDER BY aov.block_num DESC
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

CREATE OR REPLACE FUNCTION hafbe_backend.blocksearch_by_account_asc_count(
    _operations INT[],
    _account TEXT,
    _from INT, 
    _to INT,
    _limit INT
)
RETURNS INT -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
SET plan_cache_mode = force_generic_plan
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
    get_account_id AS MATERIALIZED
    (
      SELECT 
        av.id 
      FROM hive.accounts_view av 
      WHERE 
        av.name = _account
    ),
    blocks AS 
    (
      SELECT 
          aov.block_num
      FROM hive.account_operations_view aov
      WHERE 
        aov.op_type_id = ANY((SELECT op_type_ids FROM ops_list)::SMALLINT[])
        AND aov.account_id = (SELECT id FROM get_account_id)
        AND ((_to IS NULL) OR aov.block_num <= _to)
        AND ((_from IS NULL) OR aov.block_num >= _from)
      ORDER BY aov.block_num ASC
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
