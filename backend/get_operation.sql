SET ROLE hafbe_owner;

-- Function used in body returning functions that allows to limit too long operation_body (small.minion), allows FE to set desired length of operation
-- Too long operations are being replaced by placeholder with possibility of opening it in another page
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

-- used in comment history endpoint
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

-- filter too long operation bodies 
  SELECT s.permlink, s.block_num, s.id, s.timestamp, (s.composite).body, (s.composite).is_modified
  FROM (
  SELECT hafbe_backend.operation_body_filter(o.body_binary::jsonb, o.id, _body_limit) as composite, o.id, o.block_num, o.permlink, o.author, o.timestamp
  FROM operation_range o 
  ) s
  ORDER BY s.author, s.permlink, s.id;

END
$$;

-- used in comment history endpoint
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

CREATE OR REPLACE FUNCTION hafbe_backend.get_ops_by_account(
    _account TEXT,
    _page_num INT,
    _limit INT,
    _filter INT [],
    _from INT,
    _to INT,
    _body_limit INT,
    _rest_of_division INT,
    _ops_count INT
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
  __no_start_date BOOLEAN = (_from IS NULL);
  __no_end_date BOOLEAN = (_to IS NULL);
  __no_ops_filter BOOLEAN = (_filter IS NULL);
  __no_filters BOOLEAN := TRUE;
  __offset INT := (((_page_num - 2) * _limit) + (_rest_of_division));
-- offset is calculated only from _page_num = 2, then the offset = _rest_of_division
-- on _page_num = 3, offset = _limit + _rest_of_division etc.
  __op_seq INT:= 0;
BEGIN
IF __no_start_date AND __no_end_date AND __no_ops_filter THEN
  __no_filters = FALSE;
  __op_seq := (_ops_count - (((_page_num - 1) * _limit) + _rest_of_division) );
END IF;


-- 23726 - (237 * 100 + 26) = 0 >= and < 100 
-- 23726 - (236 * 100 + 26) = 100 >= and < 200  

-- 23726 - (0 * 100 + 26) = 23700 >= and < 23800  

RETURN QUERY   
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
  WITH op_filter AS MATERIALIZED (
      SELECT ARRAY_AGG(ot.id) as op_id FROM hive.operation_types ot WHERE (CASE WHEN _filter IS NOT NULL THEN ot.id = ANY(_filter) ELSE TRUE END)
  ),
-- changing filtering method from block_num to operation_id
	ops_from_start_block as MATERIALIZED
	(
		SELECT o.id 
		FROM hive.operations_view o
		WHERE o.block_num >= _from
		ORDER BY o.block_num, o.id
		LIMIT 1
	),
	ops_from_end_block as MATERIALIZED
	(
		SELECT o.id
		FROM hive.operations_view o
		WHERE o.block_num < _to
		ORDER BY o.block_num DESC, o.id DESC
		LIMIT 1
	)

  /*
  we are using 3 diffrent methods of fetching data,
  1. using hive_account_operations_uq_1 (account_id, account_op_seq_no) when __no_filters = FALSE (when 2. and 3. are TRUE)
    - when we don't use filter we can page the result by account_op_seq_no, 
      we need to add ORDER BY account_op_seq_no
  2. using hive_account_operations_uq2 (account_id, operation_id) when __no_end_date = FALSE OR __no_start_date = FALSE
    - when we filter operations ONLY by block_num (converted to operation_id), 
      we need to add ORDER BY operation_id
  3. using hive_account_operations_type_account_id_op_seq_idx (op_type_id, account_id, account_op_seq_no) when __no_ops_filter = FALSE
    - when we filter operations by op_type_id 
    - when we filter operations by op_type_id AND block_num (converted to operation_id)
  */ 

    SELECT haov.operation_id, haov.op_type_id, haov.block_num
    FROM hive.account_operations_view haov
    WHERE haov.account_id = __account_id
    AND (__no_filters OR account_op_seq_no >= __op_seq)
	  AND (__no_filters OR account_op_seq_no < (__op_seq + _limit))
    AND (__no_ops_filter OR haov.op_type_id = ANY(ARRAY[(SELECT of.op_id FROM op_filter of)]))
    AND (__no_start_date OR haov.operation_id >= (SELECT * FROM ops_from_start_block))
	  AND (__no_end_date OR haov.operation_id < (SELECT * FROM ops_from_end_block))
    ORDER BY (CASE WHEN NOT __no_start_date OR NOT __no_end_date THEN haov.operation_id WHEN NOT __no_filters THEN haov.account_op_seq_no END) DESC
    LIMIT (CASE WHEN _page_num = 1 AND (_rest_of_division) != 0 THEN _rest_of_division ELSE _limit END)
    OFFSET (CASE WHEN _page_num = 1 OR NOT __no_filters THEN 0 ELSE __offset END)
  ) ls
  JOIN hive.operations_view hov ON hov.id = ls.operation_id
  JOIN hive.operation_types hot ON hot.id = ls.op_type_id
  LEFT JOIN hive.transactions_view htv ON htv.block_num = ls.block_num AND htv.trx_in_block = hov.trx_in_block
  )

-- filter too long operation bodies 
  SELECT s.id, s.block_num, s.trx_in_block, s.trx_hash, s.op_pos, s.op_type_id, (s.composite).body, s.is_virtual, s.timestamp, s.age, (s.composite).is_modified
  FROM (
  SELECT hafbe_backend.operation_body_filter(o.body, o.id, _body_limit) as composite, o.id, o.block_num, o.trx_in_block, o.trx_hash, o.op_pos, o.op_type_id, o.is_virtual, o.timestamp, o.age
  FROM operation_range o 
  ) s
  ORDER BY s.id DESC;

END
$$;

-- used in account page endpoint
CREATE OR REPLACE FUNCTION hafbe_backend.get_account_operations_count(
    _operations INT [],
    _account TEXT,
    _from INT,
    _to INT
)
RETURNS BIGINT -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET enable_hashjoin = OFF
SET JIT = OFF
AS
$$
DECLARE
  __no_start_date BOOLEAN = (_from IS NULL);
  __no_end_date BOOLEAN = (_to IS NULL);
  __no_ops_filter BOOLEAN = (_operations IS NULL);
BEGIN
IF __no_ops_filter = TRUE AND __no_start_date = TRUE AND __no_end_date = TRUE THEN
  RETURN (
      WITH account_id AS MATERIALIZED (
        SELECT a.id FROM hive.accounts_view a WHERE a.name = _account)

      SELECT ao.account_op_seq_no + 1
      FROM hive.account_operations_view ao
      WHERE ao.account_id = (SELECT ai.id FROM account_id ai) 
      ORDER BY ao.account_op_seq_no DESC LIMIT 1);

ELSE
  RETURN (
    WITH op_filter AS MATERIALIZED (
      SELECT ARRAY_AGG(ot.id) as op_id FROM hive.operation_types ot WHERE (CASE WHEN _operations IS NOT NULL THEN ot.id = ANY(_operations) ELSE TRUE END)
    ),
    account_id AS MATERIALIZED (
      SELECT a.id FROM hive.accounts_view a WHERE a.name = _account
    ),
-- changing filtering method from block_num to operation_id
    	ops_from_start_block as MATERIALIZED
    (
      SELECT o.id 
      FROM hive.operations o
      WHERE o.block_num >= _from
      ORDER BY o.block_num, o.id
      LIMIT 1
    ),
    ops_from_end_block as MATERIALIZED
    (
      SELECT o.id
      FROM hive.operations o
      WHERE o.block_num < _to
      ORDER BY o.block_num DESC, o.id DESC
      LIMIT 1
    )
-- using hive_account_operations_uq2, we are forcing planner to use this index on (account_id,operation_id), it achives better performance results
    SELECT COUNT(*)
    FROM hive.account_operations ao
    WHERE ao.account_id = (SELECT ai.id FROM account_id ai)
    AND (__no_ops_filter OR ao.op_type_id = ANY(ARRAY[(SELECT of.op_id FROM op_filter of)]))
    AND (__no_start_date OR ao.operation_id >= (SELECT * FROM ops_from_start_block))
    AND (__no_end_date OR ao.operation_id < (SELECT * FROM ops_from_end_block))
    );

END IF;
END
$$;


RESET ROLE;
