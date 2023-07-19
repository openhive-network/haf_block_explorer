CREATE OR REPLACE FUNCTION hafbe_endpoints.get_ops_by_account(_account TEXT, _top_op_id INT = 2147483647, _limit INT = 1000, _filter SMALLINT[] = ARRAY[]::SMALLINT[], _date_start TIMESTAMP = NULL, _date_end TIMESTAMP = NULL)
RETURNS JSON
LANGUAGE 'plpgsql' STABLE
AS
$$
DECLARE
  __account_id INT;
BEGIN
  IF _top_op_id IS NULL OR _top_op_id < 0 THEN
    _top_op_id = 2147483647;
  END IF;

  IF _limit IS NULL OR _limit <= 0 THEN
    _limit = 1000;
  END IF;

  IF _top_op_id < (_limit - 1) THEN
    RETURN hafbe_exceptions.raise_ops_limit_exception(_top_op_id, _limit);
  END IF;

  IF _filter IS NULL THEN
    _filter = ARRAY[]::SMALLINT[];
  END IF;

  SELECT hafbe_backend.get_account_id(_account) INTO __account_id;

  RETURN CASE WHEN arr IS NOT NULL THEN to_json(arr) ELSE '[]'::JSON END FROM (
    SELECT ARRAY(
      SELECT hafbe_backend.get_set_of_ops_by_account(__account_id, _top_op_id, _limit, _filter, _date_start, _date_end)
    ) arr
  ) result;
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_ops_by_block(_block_num INT, _top_op_id BIGINT = 9223372036854775807, _limit INT = 1000, _filter SMALLINT[] = ARRAY[]::SMALLINT[])
RETURNS JSON
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  IF _top_op_id IS NULL OR _top_op_id < 0 THEN
    _top_op_id = 9223372036854775807;
  END IF;

  IF _limit IS NULL OR _limit <= 0 THEN
    _limit = 1000;
  END IF;

  IF _top_op_id < (_limit - 1) THEN
    RETURN hafbe_exceptions.raise_ops_limit_exception(_top_op_id, _limit);
  END IF;

  IF _block_num IS NULL THEN
    SELECT hafbe_backend.get_head_block_num() INTO _block_num;
  END IF;

  IF _filter IS NULL THEN
    _filter = ARRAY[]::SMALLINT[];
  END IF;

  RETURN CASE WHEN arr IS NOT NULL THEN to_json(arr) ELSE '[]'::JSON END FROM (
    SELECT ARRAY(
      SELECT hafbe_backend.get_set_of_ops_by_block(_block_num, _top_op_id, _limit, _filter)
    ) arr
  ) result;
END
$$
;
