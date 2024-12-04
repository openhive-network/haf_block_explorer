SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_backend.get_blocks_by_ops(
    _operations INT[],
    _account TEXT,
    _order_is hafbe_types.sort_direction, -- noqa: LT01, CP05
    _from INT, 
    _to INT,
    _page INT,
    _limit INT,
    _key_content TEXT [],
    _setof_keys JSON
)
RETURNS JSONB -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
AS
$$
DECLARE 
  result JSONB;

  -- flags
  _filter_by_account BOOLEAN := (_account IS NOT NULL);
  _filter_by_key BOOLEAN := (_key_content[1] IS NOT NULL);
  _filter_by_block BOOLEAN := (_from IS NOT NULL OR _to IS NOT NULL);
  _order_is_desc BOOLEAN := (_order_is = 'desc');
BEGIN
  CASE
    WHEN (_filter_by_account) AND (NOT _filter_by_key) AND (_order_is_desc) THEN
      result := hafbe_backend.blocksearch_by_account_desc(
        _operations,
        _account,
        _from, 
        _to,
        _page,
        _limit
      );
    WHEN (_filter_by_account) AND (NOT _filter_by_key) AND (NOT _order_is_desc) THEN
      result := hafbe_backend.blocksearch_by_account_asc(
        _operations,
        _account,
        _from, 
        _to,
        _page,
        _limit
      );
    WHEN (_filter_by_account) AND (_filter_by_key) AND (_order_is_desc) THEN
      result := hafbe_backend.blocksearch_by_account_and_key_desc(
        _operations[1],
        _account,
        _from, 
        _to,
        _page,
        _limit,
        _key_content,
        _setof_keys
      );
    WHEN (_filter_by_account) AND (_filter_by_key) AND (NOT _order_is_desc) THEN
      result := hafbe_backend.blocksearch_by_account_and_key_asc(
        _operations[1],
        _account,
        _from, 
        _to,
        _page,
        _limit,
        _key_content,
        _setof_keys
      );
    WHEN (NOT _filter_by_account) AND (NOT _filter_by_key) AND (NOT _filter_by_block) AND (_order_is_desc) THEN
      result := hafbe_backend.blocksearch_desc(
        _operations,
        _from, 
        _to,
        _page,
        _limit
      );
    WHEN (NOT _filter_by_account) AND (NOT _filter_by_key) AND (NOT _filter_by_block) AND (NOT _order_is_desc) THEN
      result := hafbe_backend.blocksearch_asc(
        _operations,
        _from, 
        _to,
        _page,
        _limit
      );
    WHEN (NOT _filter_by_account) AND (NOT _filter_by_key) AND (_filter_by_block) AND (_order_is_desc) THEN
      result := hafbe_backend.blocksearch_by_block_desc(
        _operations,
        _from, 
        _to,
        _page,
        _limit
      );
    WHEN (NOT _filter_by_account) AND (NOT _filter_by_key) AND (_filter_by_block) AND (NOT _order_is_desc) THEN
      result := hafbe_backend.blocksearch_by_block_asc(
        _operations,
        _from, 
        _to,
        _page,
        _limit
      );
    WHEN (NOT _filter_by_account) AND (_filter_by_key) AND (_order_is_desc) THEN
      result := hafbe_backend.blocksearch_by_key_desc(
        _operations[1],
        _from, 
        _to,
        _page,
        _limit,
        _key_content,
        _setof_keys
      );
    WHEN (NOT _filter_by_account) AND (_filter_by_key) AND (NOT _order_is_desc) THEN
      result := hafbe_backend.blocksearch_by_key_asc(
        _operations[1],
        _from, 
        _to,
        _page,
        _limit,
        _key_content,
        _setof_keys
      );
    ELSE
      RAISE EXCEPTION 'Invalid parameters';
  END CASE;

  RETURN result;
END
$$;

RESET ROLE;
