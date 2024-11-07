SET ROLE hafbe_owner;

-- used in comment history endpoint
CREATE OR REPLACE FUNCTION hafbe_backend.get_comment_operations(
    _author TEXT,
    _permlink TEXT,
    _operation_types INT[],
    _page_num INT,
    _page_size INT,
    _order_is hafbe_types.sort_direction, -- noqa: LT01, CP05
    _body_limit INT
)
RETURNS SETOF hafbe_types.operation -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
SET enable_hashjoin = OFF
AS
$$
DECLARE
  _offset INT := ((_page_num - 1) * _page_size);
BEGIN
RETURN QUERY
  WITH operation_range AS  
  (
    SELECT 
      ov.block_num,
      ov.id,
      ov.body,
      ov.op_pos,
      ov.trx_in_block,
      ov.op_type_id
    FROM 
      hive.operations_view ov
    WHERE 
      ov.op_type_id = ANY(_operation_types) AND 
      ov.body_binary::jsonb->'value'->>'author' = _author AND
      ov.body_binary::jsonb->'value'->>'permlink' = _permlink
    ORDER BY
      (CASE WHEN _order_is = 'desc' THEN ov.id ELSE NULL END) DESC,
      (CASE WHEN _order_is = 'asc' THEN ov.id ELSE NULL END) ASC
    OFFSET _offset
    LIMIT _page_size
  ),
  join_transactions AS 
  (
    SELECT 
      orr.body, 
      orr.block_num,
      (SELECT encode(trx_hash, 'hex') FROM hive.transactions_view where block_num = orr.block_num and trx_in_block = orr.trx_in_block) AS trx_hash,
      orr.op_pos,
      orr.op_type_id,
      bv.created_at,
      hot.is_virtual,
      orr.id, 
      orr.trx_in_block
    FROM operation_range orr
    JOIN hafd.operation_types hot ON hot.id = orr.op_type_id
    JOIN hive.blocks_view bv ON bv.num = orr.block_num 
  )
  -- filter too long operation bodies 
  SELECT 
    (filtered_operations.composite).body,
    filtered_operations.block_num,
    filtered_operations.trx_hash,
    filtered_operations.op_pos,
    filtered_operations.op_type_id,
    filtered_operations.created_at,
    filtered_operations.is_virtual,
    filtered_operations.id::TEXT,
    filtered_operations.trx_in_block::SMALLINT
  FROM (
    SELECT 
      hafah_backend.operation_body_filter(jt.body, jt.id, _body_limit) as composite, 
      jt.block_num,
      jt.trx_hash,
      jt.op_pos,
      jt.op_type_id,
      jt.created_at,
      jt.is_virtual,
      jt.id, 
      jt.trx_in_block
    FROM join_transactions jt
  ) filtered_operations
  ORDER BY
    (CASE WHEN _order_is = 'desc' THEN filtered_operations.id ELSE NULL END) DESC,
    (CASE WHEN _order_is = 'asc' THEN filtered_operations.id ELSE NULL END) ASC;

END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.get_comment_operations_count(
    _author TEXT,
    _permlink TEXT,
    _operation_types INT[]
)
RETURNS BIGINT -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE 
SET enable_hashjoin = OFF
AS
$$
BEGIN
RETURN (
  SELECT COUNT(*) as count
  FROM
    hive.operations_view ov
  WHERE 
    ov.op_type_id = ANY(_operation_types) AND 
    ov.body_binary::jsonb->'value'->>'author' = _author AND
    ov.body_binary::jsonb->'value'->>'permlink' = _permlink
);

END
$$;

RESET ROLE;
