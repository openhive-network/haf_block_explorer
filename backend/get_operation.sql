SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_backend.operation_body_filter(_body JSONB, _op_id BIGINT, _body_limit INT = 2147483647)
RETURNS hafbe_backend.operation_body_filter_result -- noqa: LT01, CP05
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
    _result hafbe_backend.operation_body_filter_result := (_body, _op_id, FALSE);
BEGIN
    IF length(_body::TEXT) > _body_limit THEN
        _result.body := jsonb_build_object(
            'type', 'body_placeholder_operation', 
            'value', jsonb_build_object(
                'org-op-id', _op_id, 
                'org-operation_type', _body->>'type', 
                'truncated_body', 'body truncated up to specified limit just for presentation purposes'
            )
        );
        _result.is_modified := TRUE;
    END IF;

    RETURN _result;
END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.get_comment_operations(
    _author TEXT,
    _permlink TEXT,
    _page_num INT,
    _page_size INT,
    _operation_types INT [],
    _from INT,
    _to INT,
    _body_limit INT
)
RETURNS SETOF hafbe_types.comment_history -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
SET enable_hashjoin = OFF
AS
$$
DECLARE
  _offset INT := (_page_num - 1) * 100;
BEGIN
  RETURN QUERY
  WITH operation_range AS MATERIALIZED (
  SELECT o.body_binary::jsonb->'value'->>'permlink' as permlink,
   o.body_binary::jsonb->'value'->>'author' as author,
   o.block_num, o.id, o.body_binary::jsonb, o.timestamp
  FROM hive.operations_view o
  WHERE 
    o.block_num BETWEEN _from AND _to AND
    o.op_type_id = ANY(_operation_types) AND 
    o.body_binary::jsonb->'value'->>'author' = _author AND
    (CASE WHEN _permlink IS NOT NULL THEN
    o.body_binary::jsonb->'value'->>'permlink' = _permlink ELSE
    TRUE END)
  ORDER BY author, permlink, o.id
  LIMIT _page_size
  OFFSET _offset)

  SELECT s.permlink, s.block_num, s.id, s.timestamp, (s.composite).body, (s.composite).is_modified
  FROM (
  SELECT hafbe_backend.operation_body_filter(o.body_binary::jsonb, o.id, _body_limit) as composite, o.id, o.block_num, o.permlink, o.author, o.timestamp
  FROM operation_range o 
  ) s
  ORDER BY s.author, s.permlink, s.id;

END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.get_comment_operations_count(
    _author TEXT,
    _permlink TEXT,
    _operation_types INT [],
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
  SELECT COUNT(*) as count
  FROM hive.operations_view o
  WHERE 
    o.block_num BETWEEN _from AND _to AND 
    o.op_type_id = ANY(_operation_types) AND 
    o.body_binary::jsonb->'value'->>'author' = _author AND
    (CASE WHEN _permlink IS NOT NULL THEN
    o.body_binary::jsonb->'value'->>'permlink' = _permlink ELSE
    TRUE
    END));

END
$$;


RESET ROLE;


CREATE OR REPLACE FUNCTION hafbe_backend.get_ops_by_account(
    _account TEXT,
    _page_num INT,
    _limit INT,
    _filter INT [],
    _date_start TIMESTAMP,
    _date_end TIMESTAMP,
    _body_limit INT
)
RETURNS SETOF hafbe_types.operation -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
COST 10000
SET JIT = OFF
SET join_collapse_limit = 16
SET from_collapse_limit = 16
AS
$$
DECLARE
  __account_id INT = hafbe_backend.get_account_id(_account);
  __no_ops_filter BOOLEAN = (CASE WHEN _filter IS NULL THEN TRUE ELSE FALSE END);
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

  WITH operation_range AS MATERIALIZED (
  SELECT
    ls.operation_id AS id,
    ls.block_num,
    hov.trx_in_block,
    encode(htv.trx_hash, 'hex') AS trx_hash,
    hov.op_pos,
    ls.op_type_id,
    hov.body,
    hot.is_virtual,
    hov.timestamp,
    NOW() - hov.timestamp AS age
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
  ORDER BY ls.operation_id DESC)

  SELECT s.id, s.block_num, s.trx_in_block, s.trx_hash, s.op_pos, s.op_type_id, (s.composite).body, s.is_virtual, s.timestamp, s.age, (s.composite).is_modified
  FROM (
  SELECT hafbe_backend.operation_body_filter(o.body, o.id,%L) as composite, o.id, o.block_num, o.trx_in_block, o.trx_hash, o.op_pos, o.op_type_id, o.is_virtual, o.timestamp, o.age
  FROM operation_range o 
  ) s
  ORDER BY s.id;

  $query$,
  __account_id,
  _top_op_id,
  __no_filters, _top_op_id, _limit,
  __no_ops_filter, _filter,
  __no_start_date, __block_start,
  __no_end_date, __block_end,
  __subq_limit,
  _body_limit
) res
;

END
$$;


CREATE OR REPLACE FUNCTION hafbe_backend.get_account_operations_count(
    _operations INT [],
    _account TEXT
)
RETURNS BIGINT -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET enable_hashjoin = OFF
SET JIT = OFF
AS
$$
BEGIN
IF _operations IS NULL THEN

    RETURN (
        WITH account_id AS MATERIALIZED (
        SELECT id FROM hive.accounts_view WHERE name = _account)

        SELECT account_op_seq_no + 1
        FROM hive.account_operations_view 
        WHERE account_id = (SELECT id FROM account_id) ORDER BY account_op_seq_no DESC LIMIT 1);
ELSE

    RETURN (
        WITH account_id AS MATERIALIZED (
        SELECT id FROM hive.accounts_view WHERE name =_account)

        SELECT COUNT(*)
        FROM hive.account_operations_view
        WHERE account_id = (SELECT id FROM account_id ) and op_type_id = ANY(_operations));
  
END IF;
END
$$;
