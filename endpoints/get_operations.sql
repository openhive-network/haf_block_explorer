SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_ops_by_account(_account TEXT, _page_num INT = 1, _limit INT = 100, _filter SMALLINT[] = ARRAY[]::SMALLINT[], _date_start TIMESTAMP = NULL, _date_end TIMESTAMP = NULL)
RETURNS SETOF hafbe_types.operation
LANGUAGE 'plpgsql' STABLE
COST 10000
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
AS
$$
DECLARE
  __account_id INT = hafbe_backend.get_account_id(_account);
  __no_ops_filter BOOLEAN = ((SELECT array_length(_filter, 1)) IS NULL);
  __no_start_date BOOLEAN = (_date_start IS NULL);
  __no_end_date BOOLEAN = (_date_end IS NULL);
  __no_filters BOOLEAN;
  __subq_limit INT;
  __lastest_account_op_seq_no INT;
  __block_start INT;
  __block_end INT;
  _top_op_id INT ;
BEGIN
IF __no_ops_filter AND __no_start_date AND __no_end_date THEN
  SELECT TRUE INTO __no_filters;
  SELECT NULL INTO __subq_limit;
ELSE
  SELECT FALSE INTO __no_filters;
  SELECT _limit INTO __subq_limit;
END IF;

SELECT INTO __lastest_account_op_seq_no
  account_op_seq_no FROM hive.account_operations_view WHERE account_id = __account_id ORDER BY account_op_seq_no DESC LIMIT 1;
SELECT GREATEST(__lastest_account_op_seq_no - ((_page_num - 1) * 100), 0) INTO _top_op_id;

IF __no_start_date IS FALSE THEN
  SELECT num FROM hive.blocks_view hbv WHERE hbv.created_at >= _date_start ORDER BY created_at ASC LIMIT 1 INTO __block_start;
END IF;
IF __no_end_date IS FALSE THEN  
  SELECT num FROM hive.blocks_view hbv WHERE hbv.created_at < _date_end ORDER BY created_at DESC LIMIT 1 INTO __block_end;
END IF;

RETURN QUERY EXECUTE format(
  $query$

  SELECT
    ls.operation_id,
    ls.block_num,
    hov.trx_in_block,
    encode(htv.trx_hash, 'hex'),
    hov.op_pos,
    ls.op_type_id,
    hov.body,
    hot.is_virtual,
    hov.timestamp,
    NOW() - hov.timestamp
  FROM (
    SELECT haov.operation_id, haov.op_type_id, haov.block_num, haov.account_op_seq_no
    FROM hive.account_operations_view haov
    WHERE
      haov.account_id = %L::INT AND 
      haov.account_op_seq_no <= %L::INT AND
      (NOT %L OR haov.account_op_seq_no > %L::INT - %L::INT) AND
      (%L OR haov.op_type_id = ANY(%L)) AND
      (%L OR haov.block_num >= %L::INT) AND
      (%L OR haov.block_num < %L::INT)
    ORDER BY haov.operation_id DESC
    LIMIT %L
  ) ls
  JOIN hive.operations_view hov ON hov.id = ls.operation_id
  JOIN hive.operation_types hot ON hot.id = ls.op_type_id
  LEFT JOIN hive.transactions_view htv ON htv.block_num = ls.block_num AND htv.trx_in_block = hov.trx_in_block
  ORDER BY ls.operation_id DESC;

  $query$,
  __account_id,
  _top_op_id,
  __no_filters, _top_op_id, _limit,
  __no_ops_filter, _filter,
  __no_start_date, __block_start,
  __no_end_date, __block_end,
  __subq_limit
) res
;

END
$$
;

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_ops_by_block(_block_num INT, _top_op_id BIGINT = 9223372036854775807, _limit INT = 1000, _filter SMALLINT[] = ARRAY[]::SMALLINT[])
RETURNS SETOF hafbe_types.operation
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
AS
$$
DECLARE
  __no_ops_filter BOOLEAN = ((SELECT array_length(_filter, 1)) IS NULL);
BEGIN
RETURN QUERY SELECT
  ls.id,
  ls.block_num,
  ls.trx_in_block,
  encode(htv.trx_hash, 'hex'),
  ls.op_pos,
  ls.op_type_id,
  ls.body,
  hot.is_virtual,
  ls.timestamp,
  NOW() - ls.timestamp
FROM (
  SELECT hov.id, hov.trx_in_block, hov.op_pos, hov.timestamp, hov.body, hov.op_type_id, hov.block_num
  FROM hive.operations_view hov
  WHERE
    hov.block_num = _block_num AND
    hov.id <= _top_op_id AND 
    (__no_ops_filter OR hov.op_type_id = ANY(_filter))
  ORDER BY hov.id DESC
  LIMIT _limit
) ls
JOIN hive.operation_types hot ON hot.id = ls.op_type_id
LEFT JOIN hive.transactions_view htv ON htv.block_num = ls.block_num AND htv.trx_in_block = ls.trx_in_block
ORDER BY ls.id DESC
;

END
$$
;

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_operation(_operation_id INT)
RETURNS hafbe_types.operation
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
RETURN (
  SELECT ROW (
      o.id,
      o.block_num,
      o.trx_in_block,
      encode(htv.trx_hash, 'hex'),
      o.op_pos,
      o.op_type_id,
      o.body,
      hot.is_virtual,
      o.timestamp,
      NOW() - o.timestamp)
    FROM hive.operations_view o 
    JOIN hive.operation_types hot ON hot.id = o.op_type_id
    LEFT JOIN hive.transactions_view htv ON htv.block_num = o.block_num AND htv.trx_in_block = o.trx_in_block
	  WHERE o.id = _operation_id
);

END
$$
;

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_operation_keys(_operation_id INT)
RETURNS SETOF TEXT[]
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
SET enable_bitmapscan = OFF
--enable_bitmapscan = OFF helps with perfomance on database with smaller number of blocks (tested od 12m blocks, planner choses wrong plan and the query is slow)
AS
$$
DECLARE
	_example_key JSON := (SELECT o.body FROM hive.operations_view o WHERE o.op_type_id = _operation_id LIMIT 1);
BEGIN
RETURN QUERY
WITH RECURSIVE extract_keys AS (
  SELECT 
    ARRAY['value']::TEXT[] as key_path, 
    (json_each(_example_key -> 'value')).*
  UNION ALL
  SELECT 
    key_path || key,
    (json_each(value)).*
  FROM 
    extract_keys
  WHERE 
    json_typeof(value) = 'object'
)
SELECT 
  key_path || key as full_key_path
FROM 
  extract_keys
WHERE 
  json_typeof(value) != 'object'
;

END
$$
;


RESET ROLE;
