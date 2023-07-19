CREATE OR REPLACE FUNCTION hafbe_endpoints.get_head_block_num()
RETURNS INT
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN hafbe_backend.get_head_block_num();
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_block(_block_num INT)
RETURNS JSON
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  IF _block_num IS NULL THEN
    SELECT hafbe_backend.get_head_block_num() INTO _block_num;
  END IF;

  RETURN CASE WHEN arr IS NOT NULL THEN to_json(arr) ELSE '[]'::JSON END FROM (
    SELECT ARRAY(
      SELECT hafbe_backend.get_set_of_block_data(_block_num)
    ) arr
  ) result;
END
$$
;
