SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_backend.get_comment_permlinks(
    _author TEXT,
    _comment_type hafbe_types.comment_type,
    _page_num INT,
    _page_size INT,
    _from INT,
    _to INT
)
RETURNS SETOF hafbe_types.permlink_history -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
SET enable_hashjoin = OFF
AS
$$
DECLARE
  _offset INT := ((_page_num - 1) * _page_size);
BEGIN
RETURN QUERY
  WITH permlink_range AS  
  (
    SELECT 
      ov.id,
      ov.body_binary::jsonb->'value'->>'permlink' as permlink
    FROM 
      hive.operations_view ov
    WHERE 
      op_type_id = 1 AND  
      ov.body_binary::jsonb->'value'->>'author' = _author AND
      ((_to IS NULL) OR ov.block_num <= _to) AND
      ((_from IS NULL) OR ov.block_num >= _from) AND
      ((_comment_type = 'post' AND ov.body_binary::jsonb->'value'->>'parent_author' = '') OR
      (_comment_type = 'comment' AND ov.body_binary::jsonb->'value'->>'parent_author' != '') OR
      (_comment_type = 'all'))
    ORDER BY ov.id DESC
  ),
  permlink_list AS 
  (
    SELECT 
      permlink,
      MAX(id) AS id
    FROM permlink_range
    GROUP BY permlink
	  ORDER BY id DESC
    OFFSET _offset
    LIMIT _page_size
  ),
  join_operations AS 
  (
    SELECT 
      ov.block_num,
      pl.id, 
      pl.permlink, 
      ov.trx_in_block
    FROM permlink_list pl
    JOIN hive.operations_view ov ON ov.id = pl.id
  )
  SELECT 
    jo.permlink,
    jo.block_num,
    (SELECT encode(trx_hash, 'hex') FROM hive.transactions_view where block_num = jo.block_num and trx_in_block = jo.trx_in_block) AS trx_hash,
    bv.created_at,
    jo.id::TEXT
  FROM join_operations jo
--The query planner, based on statistics, determined that a large amount of data would be joined from both the left and right sides, and chose a merge join as the optimal strategy
--This approach is incorrect - we use subquery to find trx_hash
--JOIN hive.transactions_view htv ON htv.block_num = jo.block_num AND htv.trx_in_block = jo.trx_in_block
  JOIN hive.blocks_view bv ON bv.num = jo.block_num 
  ORDER BY jo.id DESC;

END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.get_comment_permlinks_count(
    _author TEXT,
    _comment_type hafbe_types.comment_type,
    _from INT,
    _to INT
)
RETURNS BIGINT -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE 
SET enable_hashjoin = OFF
AS
$$
BEGIN
RETURN (
  WITH agg_permlink AS
  (
    SELECT 
      ov.body_binary::jsonb->'value'->>'permlink' as permlink
    FROM
      hive.operations_view ov
    WHERE 
      ov.op_type_id = 1 AND 
      ov.body_binary::jsonb->'value'->>'author' = _author AND
      ((_from IS NULL) OR ov.block_num >= _from) AND
      ((_to IS NULL) OR ov.block_num <= _to) AND
      ((_comment_type = 'post' AND ov.body_binary::jsonb->'value'->>'parent_author' = '') OR
      (_comment_type = 'comment' AND ov.body_binary::jsonb->'value'->>'parent_author' != '') OR
      (_comment_type = 'all'))
    GROUP BY ov.body_binary::jsonb->'value'->>'permlink'
  )
  SELECT COUNT(*) FROM agg_permlink
);

END
$$;

RESET ROLE;
