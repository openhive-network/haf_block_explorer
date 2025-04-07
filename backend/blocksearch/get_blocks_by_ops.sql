SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_backend.get_blocks_by_ops(
    _operations INT[],
    _account INT,
    _order_is hafbe_types.sort_direction, -- noqa: LT01, CP05
    _from INT, 
    _to INT,
    _page INT,
    _limit INT,
    _key_content TEXT [],
    _setof_keys JSON
)
RETURNS JSON -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
AS
$$
DECLARE 
  result JSON;

  -- flags
  _filter_by_op BOOLEAN:= (_operations IS NOT NULL);
  _filter_by_single_op BOOLEAN := (CASE WHEN (_operations IS NOT NULL) AND (array_length(_operations, 1) = 1) THEN TRUE ELSE FALSE END);
  _filter_by_account BOOLEAN := (_account IS NOT NULL);
  _filter_by_key BOOLEAN := (_key_content[1] IS NOT NULL);
BEGIN
  
  CASE
    WHEN (NOT _filter_by_op) AND (NOT _filter_by_account) AND (NOT _filter_by_key) THEN
      result := hafbe_backend.blocksearch_no_filter(
        _from,
        _to,
        _order_is, 
        _page,
        _limit
      );
    WHEN (_filter_by_single_op) AND (NOT _filter_by_account) AND (NOT _filter_by_key) THEN
      result := hafbe_backend.blocksearch_single_op(
        _operations[1],
        _from,
        _to,
        _order_is, 
        _page,
        _limit
      );
    WHEN (_filter_by_op) AND (NOT _filter_by_single_op) AND (NOT _filter_by_account) AND (NOT _filter_by_key) THEN
      result := hafbe_backend.blocksearch_multi_op(
        _operations,
        _from,
        _to,
        _order_is, 
        _page,
        _limit
      );
    WHEN (_filter_by_single_op) AND (NOT _filter_by_account) AND (_filter_by_key) THEN
      result := hafbe_backend.blocksearch_key_value(
        _operations[1],
        _from,
        _to,
        _order_is, 
        _page,
        _limit,
        _key_content,
        _setof_keys
      );
    WHEN (NOT _filter_by_op) AND (_filter_by_account) AND (NOT _filter_by_key) THEN
      result := hafbe_backend.blocksearch_account(
        _account,
        _from,
        _to,
        _order_is, 
        _page,
        _limit
      );
    WHEN (_filter_by_single_op) AND (_filter_by_account) AND (NOT _filter_by_key) THEN
      result := hafbe_backend.blocksearch_account_op(
        _operations[1],
        _account,
        _from,
        _to,
        _order_is, 
        _page,
        _limit
      );
    WHEN (_filter_by_op) AND (NOT _filter_by_single_op) AND (_filter_by_account) AND (NOT _filter_by_key) THEN
      result := hafbe_backend.blocksearch_account_multi_op(
        _operations,
        _account,
        _from,
        _to,
        _order_is, 
        _page,
        _limit
      );
    WHEN (_filter_by_single_op) AND (_filter_by_account) AND (_filter_by_key) THEN
      result := hafbe_backend.blocksearch_account_key_value(
        _operations[1],
        _account,
        _from,
        _to,
        _order_is, 
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
