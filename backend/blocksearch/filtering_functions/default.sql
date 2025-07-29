SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_backend.blocksearch_no_filter(
    _from INT, 
    _to INT,
    _order_is hafbe_types.sort_direction, -- noqa: LT01, CP05
    _page INT,
    _limit INT
)
RETURNS hafbe_types.block_history -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET JIT = OFF
AS
$$
DECLARE 
  __hafbe_current_block INT := (SELECT current_block_num FROM hafd.contexts WHERE name = 'hafbe_app');

  __count INT;
  __from INT;
  __to INT;

  __rest_of_division INT;
  __total_pages INT;
  __page INT;
  __offset INT;
  __limit INT;

  _result hafbe_types.blocksearch[];
BEGIN
  -----------PAGING LOGIC----------------
  SELECT count_blocks, from_block, to_block
  INTO __count, __from, __to
  FROM hafbe_backend.blocksearch_no_filter_count(_from, _to, __hafbe_current_block);

  SELECT rest_of_division, total_pages, page_num, offset_filter, limit_filter
  INTO __rest_of_division, __total_pages, __page, __offset, __limit
  FROM hafbe_backend.blocksearch_calculate_pages(__count, _page, _order_is, _limit);

  --RAISE NOTICE 'blocksearch_no_filter_desc: __from: %, __to: %, __page: %, _limit: %, __count: %, __total_pages: %, __rest_of_division: %, __offset: %', __from, __to, __page, _limit, __count, __total_pages, __rest_of_division, __offset;

  IF __total_pages = 0 THEN
    RETURN (
      __count,
      __total_pages,
      (__from, __to)::hafbe_types.block_range,
      '{}'::hafbe_types.blocksearch[]
    )::hafbe_types.block_history;
  END IF;

  _result := array_agg(row ORDER BY
      (CASE WHEN _order_is = 'desc' THEN row.block_num ELSE NULL END) DESC,
      (CASE WHEN _order_is = 'asc' THEN row.block_num ELSE NULL END) ASC
    ) FROM (
      SELECT 
        bv.num AS block_num,
        bv.created_at, 
        hafah_backend.get_account_name(bv.producer_account_id) AS producer_account,
        hafbe_backend.get_producer_reward(bv.num)::TEXT AS producer_reward,
        hafbe_backend.get_trx_count(bv.num) AS trx_count,
        encode(bv.hash, 'hex') AS hash,
        encode(bv.prev, 'hex') AS prev,
        hafbe_backend.get_block_operation_aggregation(bv.num) AS operations
      FROM hive.blocks_view bv 
      WHERE
        bv.num >= __from AND
        bv.num <= __to  AND
        (_order_is = 'desc' OR bv.num >= __from + __offset) AND
        (_order_is = 'asc' OR bv.num <= __to - __offset)
      ORDER BY
        (CASE WHEN _order_is = 'desc' THEN bv.num ELSE NULL END) DESC,
        (CASE WHEN _order_is = 'asc' THEN bv.num ELSE NULL END) ASC
      LIMIT __limit
  ) row;

  RETURN (
    COALESCE(__count, 0),
    COALESCE(__total_pages, 0),
    (__from, __to)::hafbe_types.block_range,
    COALESCE(_result, '{}'::hafbe_types.blocksearch[])
  )::hafbe_types.block_history;

END
$$;

RESET ROLE;
