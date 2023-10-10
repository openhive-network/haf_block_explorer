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

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_witness_voters(_witness TEXT, _order_by TEXT = 'vests', _order_is TEXT = 'desc', _limit INT = 2147483647)
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

  IF _order_is NOT SIMILAR TO '(asc|desc)' THEN
    RETURN hafbe_exceptions.raise_no_such_order_exception(_order_is);
  END IF;

  RETURN CASE WHEN arr IS NOT NULL THEN to_json(arr) ELSE '[]'::JSON END FROM (
    SELECT ARRAY(
      SELECT hafbe_backend.get_set_of_witness_voters(__witness_id, _order_by, _order_is, _limit)
    ) arr
  ) result;
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_witness_votes_history(_witness TEXT, _order_by TEXT = 'timestamp', _order_is TEXT = 'desc', _limit INT = 100, _from_time TIMESTAMP='1970-01-01T00:00:00'::TIMESTAMP, _to_time TIMESTAMP=NOW())
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

  IF _order_is NOT SIMILAR TO '(asc|desc)' THEN
    RETURN hafbe_exceptions.raise_no_such_order_exception(_order_is);
  END IF;

  RETURN CASE WHEN arr IS NOT NULL THEN to_json(arr) ELSE '[]'::JSON END FROM (
    SELECT ARRAY(
      SELECT hafbe_backend.get_set_of_witness_votes_history(__witness_id, _order_by, _order_is, _limit, _from_time, _to_time)
    ) arr
  ) result;
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_witnesses(_limit INT = 100, _offset INT = 0, _order_by TEXT = 'votes', _order_is TEXT = 'desc')
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  IF _order_by NOT SIMILAR TO
    '(witness|rank|url|votes|votes_daily_change|voters_num|voters_num_daily_change|price_feed|bias|feed_age|block_size|signing_key|version)' THEN
    RETURN hafbe_exceptions.raise_no_such_column_exception(_order_by);
  END IF;

  IF _order_is NOT SIMILAR TO '(asc|desc)' THEN
    RETURN hafbe_exceptions.raise_no_such_order_exception(_order_is);
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