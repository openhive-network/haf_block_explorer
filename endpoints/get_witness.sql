CREATE OR REPLACE FUNCTION hafbe_endpoints.get_witness_voters_num(_witness TEXT)
RETURNS INT
LANGUAGE 'plpgsql' STABLE
AS
$$
DECLARE
  __witness_id INT = hafbe_backend.get_account_id(_witness);
BEGIN
  RETURN hafbe_backend.get_witness_voters_num(__witness_id);
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_witness_voters(_witness TEXT, _order_by TEXT = 'vests', _order_is TEXT = 'desc')
RETURNS JSON
LANGUAGE 'plpgsql' STABLE
AS
$$
DECLARE
  __witness_id INT = hafbe_backend.get_account_id(_witness);
BEGIN
  IF _order_by NOT SIMILAR TO '(voter|vests|account_vests|proxied_vests|timestamp)' THEN
    RETURN hafbe_exceptions.raise_no_such_column_exception(_order_by);
  END IF;
  IF _order_by IS NULL THEN
    _order_by = 'vests';
  END IF;

  IF _order_is NOT SIMILAR TO '(asc|desc)' THEN
    RETURN hafbe_exceptions.raise_no_such_order_exception(_order_is);
  END IF;
  IF _order_is IS NULL THEN
    _order_is = 'desc';
  END IF;

  RETURN CASE WHEN arr IS NOT NULL THEN to_json(arr) ELSE '[]'::JSON END FROM (
    SELECT ARRAY(
      SELECT hafbe_backend.get_set_of_witness_voters(__witness_id, _order_by, _order_is)
    ) arr
  ) result;

END
$$
;

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_witness_voters_daily_change(_witness TEXT, _limit INT = 1000, _offset INT = 0, _order_by TEXT = 'vests', _order_is TEXT = 'desc')
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __witness_id INT = hafbe_backend.get_account_id(_witness);
BEGIN
  IF _limit IS NULL OR _limit <= 0 THEN
    _limit = 1000;
  END IF;

  IF _offset IS NULL OR _offset < 0 THEN
    _offset = 0;
  END IF;

  IF _order_by NOT SIMILAR TO '(voter|vests|account_vests|proxied_vests|timestamp)' THEN
    RETURN hafbe_exceptions.raise_no_such_column_exception(_order_by);
  END IF;
  IF _order_by IS NULL THEN
    _order_by = 'vests';
  END IF;

  IF _order_is NOT SIMILAR TO '(asc|desc)' THEN
    RETURN hafbe_exceptions.raise_no_such_order_exception(_order_is);
  END IF;
  IF _order_is IS NULL THEN
    _order_is = 'desc';
  END IF;

  RETURN CASE WHEN arr IS NOT NULL THEN to_json(arr) ELSE '[]'::JSON END FROM (
    SELECT ARRAY(
      SELECT hafbe_backend.get_set_of_witness_voters_daily_change(__witness_id, _limit, _offset, _order_by, _order_is)
    ) arr
  ) result;
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_witnesses(_limit INT = 1000, _offset INT = 0, _order_by TEXT = 'votes', _order_is TEXT = 'desc')
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  IF _limit IS NULL OR _limit <= 0 THEN
    _limit = 1000;
  END IF;

  IF _offset IS NULL OR _offset < 0 THEN
    _offset = 0;
  END IF;

  IF _order_by NOT SIMILAR TO
    '(witness|rank|url|votes|votes_daily_change|voters_num|voters_num_daily_change|price_feed|bias|feed_age|block_size|signing_key|version)' THEN
    RETURN hafbe_exceptions.raise_no_such_column_exception(_order_by);
  END IF;
  IF _order_by IS NULL THEN
    _order_by = 'votes';
  END IF;

  IF _order_is NOT SIMILAR TO '(asc|desc)' THEN
    RETURN hafbe_exceptions.raise_no_such_order_exception(_order_is);
  END IF;
  IF _order_is IS NULL THEN
    _order_is = 'desc';
  END IF;

    RETURN CASE WHEN arr IS NOT NULL THEN to_json(arr) ELSE '[]'::JSON END FROM (
      SELECT ARRAY(
        SELECT hafbe_backend.get_set_of_witnesses(_limit, _offset, _order_by, _order_is)
      ) arr
    ) result;
END
$$
;


CREATE OR REPLACE FUNCTION hafbe_endpoints.get_witness(_account TEXT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN

RETURN CASE WHEN arr IS NOT NULL THEN to_json(arr) ELSE '[]'::JSON END FROM (
  SELECT ARRAY(
    SELECT hafbe_backend.get_setof_witness(_account)
  ) arr
) result;

END
$$
;