CREATE OR REPLACE FUNCTION hafbe_backend.get_trx_hash(_block_num INT, _trx_in_block INT)
RETURNS TEXT
LANGUAGE 'plpgsql'
AS 
$$
BEGIN
  RETURN encode(trx_hash, 'hex')
  FROM hive.transactions_view htv
  WHERE htv.block_num = _block_num AND htv.trx_in_block = _trx_in_block;
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_backend.get_set_of_ops_by_account(_account_id INT, _top_op_id INT, _limit INT, _filter SMALLINT[], _date_start TIMESTAMP, _date_end TIMESTAMP)
RETURNS SETOF hafbe_types.operations
AS
$function$
DECLARE
  __no_ops_filter BOOLEAN = ((SELECT array_length(_filter, 1)) IS NULL);
  __no_start_date BOOLEAN = (_date_start IS NULL);
  __no_end_date BOOLEAN = (_date_end IS NULL);
  __no_filters BOOLEAN;
  __subq_limit INT;
  __lastest_account_op_seq_no INT;
  __block_start INT;
  __block_end INT;
BEGIN
  IF __no_ops_filter AND __no_start_date AND __no_end_date THEN
    SELECT TRUE INTO __no_filters;
    SELECT NULL INTO __subq_limit;
    SELECT INTO __lastest_account_op_seq_no
      account_op_seq_no FROM hive.account_operations_view WHERE account_id = _account_id ORDER BY account_op_seq_no DESC LIMIT 1;
    SELECT INTO _top_op_id
      CASE WHEN __lastest_account_op_seq_no < _top_op_id THEN __lastest_account_op_seq_no ELSE _top_op_id END; 
  ELSE
    SELECT FALSE INTO __no_filters;
    SELECT _limit INTO __subq_limit;
  END IF;

  IF __no_start_date IS FALSE THEN
    SELECT num FROM hive.blocks_view hbv WHERE hbv.created_at >= _date_start ORDER BY created_at ASC LIMIT 1 INTO __block_start;
  END IF;
  IF __no_end_date IS FALSE THEN
    SELECT num FROM hive.blocks_view hbv WHERE hbv.created_at < _date_end ORDER BY created_at DESC LIMIT 1 INTO __block_end;
  END IF;

  RETURN QUERY EXECUTE format(
    $query$
    
    SELECT
      encode(htv.trx_hash, 'hex'),
      ls.block_num,
      hov.trx_in_block,
      hov.op_pos,
      hot.is_virtual,
      hov.timestamp,
      NOW() - hov.timestamp,
      hov.body::JSONB,
      ls.operation_id,
      ls.account_op_seq_no
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
    _account_id,
    _top_op_id,
    __no_filters, _top_op_id, _limit,
    __no_ops_filter, _filter,
    __no_start_date, __block_start,
    __no_end_date, __block_end,
    __subq_limit
  ) res;
END
$function$
LANGUAGE 'plpgsql' STABLE
COST 10000
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
;

CREATE OR REPLACE FUNCTION hafbe_backend.get_set_of_ops_by_block(_block_num INT, _top_op_id BIGINT, _limit INT, _filter SMALLINT[])
RETURNS SETOF hafbe_types.operations 
AS
$function$
DECLARE
  __no_ops_filter BOOLEAN = ((SELECT array_length(_filter, 1)) IS NULL);
BEGIN
  RETURN QUERY SELECT
    encode(htv.trx_hash, 'hex'),
    ls.block_num,
    ls.trx_in_block,
    ls.op_pos,
    hot.is_virtual,
    ls.timestamp,
    NOW() - ls.timestamp,
    ls.body::JSONB,
    ls.id,
    NULL::INT
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
  ORDER BY ls.id DESC;
END
$function$
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
;
