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
                'org-op-id', _op_id::TEXT, 
                'org-operation_type', _body->>'type', 
                'truncated_body', 'body truncated up to specified limit just for presentation purposes'
            )
        );
        _result.is_modified := TRUE;
    END IF;

    RETURN _result;
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
    ov.trx_in_block,
    encode(htv.trx_hash, 'hex') AS trx_hash,
    ov.op_pos,
    ls.op_type_id,
    ov.body,
    hot.is_virtual
  FROM (
  WITH op_filter AS MATERIALIZED (
      SELECT ARRAY_AGG(ot.id) as op_id FROM hive.operation_types ot WHERE (CASE WHEN _filter IS NOT NULL THEN ot.id = ANY(_filter) ELSE TRUE END)
  ),
-- changing filtering method from block_num to operation_id
	ops_from_start_block as MATERIALIZED
	(
		SELECT ov.id 
		FROM hive.operations_view ov
		WHERE ov.block_num >= _from
		ORDER BY ov.block_num, ov.id
		LIMIT 1
	),
	ops_from_end_block as MATERIALIZED
	(
		SELECT ov.id
		FROM hive.operations_view ov
		WHERE ov.block_num <= _to
		ORDER BY ov.block_num DESC, ov.id DESC
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

    SELECT aov.operation_id, aov.op_type_id, aov.block_num
    FROM hive.account_operations_view aov
    WHERE aov.account_id = __account_id
    AND (__no_filters OR account_op_seq_no >= (CASE WHEN (_rest_of_division) != 0 THEN __op_seq ELSE (__op_seq - _limit) END))
	  AND (__no_filters OR account_op_seq_no < (CASE WHEN (_rest_of_division) != 0 THEN (__op_seq + _limit) ELSE __op_seq END))
    AND (__no_ops_filter OR aov.op_type_id = ANY(ARRAY[(SELECT of.op_id FROM op_filter of)]))
    AND (__no_start_date OR aov.operation_id >= (SELECT * FROM ops_from_start_block))
	  AND (__no_end_date OR aov.operation_id < (SELECT * FROM ops_from_end_block))
    ORDER BY (CASE WHEN NOT __no_start_date OR NOT __no_end_date THEN aov.operation_id ELSE aov.account_op_seq_no END) DESC
    LIMIT (CASE WHEN _page_num = 1 AND (_rest_of_division) != 0 THEN _rest_of_division ELSE _limit END)
    OFFSET (CASE WHEN _page_num = 1 OR NOT __no_filters THEN 0 ELSE __offset END)
  ) ls
  JOIN hive.operations_view ov ON ov.id = ls.operation_id
  JOIN hive.operation_types hot ON hot.id = ls.op_type_id
  LEFT JOIN hive.transactions_view htv ON htv.block_num = ls.block_num AND htv.trx_in_block = ov.trx_in_block
  )

-- filter too long operation bodies 
  SELECT filtered_operations.id::TEXT, filtered_operations.block_num, filtered_operations.trx_in_block, filtered_operations.trx_hash, filtered_operations.op_pos, filtered_operations.op_type_id, (filtered_operations.composite).body, filtered_operations.is_virtual, filtered_operations.timestamp, filtered_operations.age, (filtered_operations.composite).is_modified
  FROM (
  SELECT hafbe_backend.operation_body_filter(ov.body, ov.id, _body_limit) as composite, ov.id, ov.block_num, ov.trx_in_block, ov.trx_hash, ov.op_pos, ov.op_type_id, ov.is_virtual, hb.created_at timestamp, NOW() - hb.created_at AS age
  FROM operation_range ov 
  JOIN hive.blocks_view hb ON hb.num = ov.block_num
  ) filtered_operations
  ORDER BY filtered_operations.id DESC;

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
        SELECT av.id FROM hive.accounts_view av WHERE av.name = _account)

      SELECT aov.account_op_seq_no + 1
      FROM hive.account_operations_view aov
      WHERE aov.account_id = (SELECT ai.id FROM account_id ai) 
      ORDER BY aov.account_op_seq_no DESC LIMIT 1);

ELSE
  RETURN (
    WITH op_filter AS MATERIALIZED (
      SELECT ARRAY_AGG(ot.id) as op_id FROM hive.operation_types ot WHERE (CASE WHEN _operations IS NOT NULL THEN ot.id = ANY(_operations) ELSE TRUE END)
    ),
    account_id AS MATERIALIZED (
      SELECT av.id FROM hive.accounts_view av WHERE av.name = _account
    ),
-- changing filtering method from block_num to operation_id
    	ops_from_start_block as MATERIALIZED
    (
      SELECT ov.id 
      FROM hive.operations_view ov
      WHERE ov.block_num >= _from
      ORDER BY ov.block_num, ov.id
      LIMIT 1
    ),
    ops_from_end_block as MATERIALIZED
    (
      SELECT ov.id
      FROM hive.operations_view ov
      WHERE ov.block_num <= _to
      ORDER BY ov.block_num DESC, ov.id DESC
      LIMIT 1
    )
-- using hive_account_operations_uq2, we are forcing planner to use this index on (account_id,operation_id), it achives better performance results
    SELECT COUNT(*)
    FROM hive.account_operations_view aov
    WHERE aov.account_id = (SELECT ai.id FROM account_id ai)
    AND (__no_ops_filter OR aov.op_type_id = ANY(ARRAY[(SELECT of.op_id FROM op_filter of)]))
    AND (__no_start_date OR aov.operation_id >= (SELECT * FROM ops_from_start_block))
    AND (__no_end_date OR aov.operation_id < (SELECT * FROM ops_from_end_block))
    );

END IF;
END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.get_ops_by_block(
    _block_num INT,
    _page_num INT,
    _page_size INT,
    _filter INT [],
    _order_is hafbe_types.sort_direction, -- noqa: LT01, CP05
    _body_limit INT,
    _account TEXT,
    _key_content TEXT [],
    _setof_keys JSON
)
RETURNS SETOF hafbe_types.operation -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
SET JIT = OFF
SET join_collapse_limit = 16
SET from_collapse_limit = 16
AS
$$
DECLARE
  __no_ops_filter BOOLEAN = (_filter IS NULL);
  _offset INT := (_page_num - 1) * _page_size;
  _first_key BOOLEAN = (_key_content[1] IS NULL);
  _second_key BOOLEAN = (_key_content[2] IS NULL);
  _third_key BOOLEAN = (_key_content[3] IS NULL);
BEGIN

IF _account IS NULL THEN
  RETURN QUERY 
  WITH operation_range AS MATERIALIZED (
    SELECT
      ls.id,
      ls.block_num,
      ls.trx_in_block,
      encode(htv.trx_hash, 'hex') AS trx_hash,
      ls.op_pos,
      ls.op_type_id,
      ls.body,
      hot.is_virtual
    FROM (
      With operations_in_block AS 
      (
      SELECT ov.id, ov.trx_in_block, ov.op_pos, ov.body, ov.op_type_id, ov.block_num
      FROM hive.operations_view ov
      WHERE
        ov.block_num = _block_num 
      ),
      filter_ops AS MATERIALIZED 
      (
      SELECT *
      FROM operations_in_block oib 
      WHERE 
        (__no_ops_filter OR oib.op_type_id = ANY(_filter)) AND
        (_first_key OR jsonb_extract_path_text(oib.body, variadic ARRAY(SELECT json_array_elements_text(_setof_keys->0))) = _key_content[1]) AND
        (_second_key OR jsonb_extract_path_text(oib.body, variadic ARRAY(SELECT json_array_elements_text(_setof_keys->1))) = _key_content[2]) AND
        (_third_key OR jsonb_extract_path_text(oib.body, variadic ARRAY(SELECT json_array_elements_text(_setof_keys->2))) = _key_content[3])
      )
      SELECT * FROM filter_ops fo
      ORDER BY
        (CASE WHEN _order_is = 'desc' THEN fo.id ELSE NULL END) DESC,
        (CASE WHEN _order_is = 'asc' THEN fo.id ELSE NULL END) ASC
      LIMIT _page_size
      OFFSET _offset
    ) ls
    JOIN hive.operation_types hot ON hot.id = ls.op_type_id
    LEFT JOIN hive.transactions_view htv ON htv.block_num = ls.block_num AND htv.trx_in_block = ls.trx_in_block
    ORDER BY
      (CASE WHEN _order_is = 'desc' THEN ls.id ELSE NULL END) DESC,
      (CASE WHEN _order_is = 'asc' THEN ls.id ELSE NULL END) ASC)

  -- filter too long operation bodies 
    SELECT filtered_operations.id::TEXT, filtered_operations.block_num, filtered_operations.trx_in_block, filtered_operations.trx_hash, filtered_operations.op_pos, filtered_operations.op_type_id,
    (filtered_operations.composite).body, filtered_operations.is_virtual, filtered_operations.timestamp, filtered_operations.age, (filtered_operations.composite).is_modified
    FROM (
    SELECT hafbe_backend.operation_body_filter(opr.body, opr.id, _body_limit) as composite, opr.id, opr.block_num, opr.trx_in_block, opr.trx_hash, opr.op_pos, opr.op_type_id, opr.is_virtual, hb.created_at timestamp, NOW() - hb.created_at AS age
    FROM operation_range opr
    JOIN hive.blocks_view hb ON hb.num = opr.block_num
    ) filtered_operations
    ORDER BY filtered_operations.id, filtered_operations.trx_in_block, filtered_operations.op_pos;

ELSE

  RETURN QUERY 
  WITH operation_range AS MATERIALIZED (
    SELECT
      ls.id,
      ls.block_num,
      ls.trx_in_block,
      encode(htv.trx_hash, 'hex') AS trx_hash,
      ls.op_pos,
      ls.op_type_id,
      ls.body,
      hot.is_virtual
    FROM (
      WITH account_operations_in_block AS 
      (
        SELECT aov.operation_id
        FROM hive.account_operations_view aov
        WHERE
          aov.account_id = (SELECT av.id FROM hive.accounts_view av WHERE av.name = _account ) AND
          aov.block_num = _block_num 
      ),
      operations_in_block AS 
      (
        SELECT ov.id, ov.trx_in_block, ov.op_pos, ov.body, ov.op_type_id, ov.block_num
        FROM hive.operations_view ov
        JOIN account_operations_in_block aoib ON aoib.operation_id = ov.id
      ),
      filter_ops AS MATERIALIZED 
      (
        SELECT *
        FROM operations_in_block oib 
        WHERE 
          (__no_ops_filter OR oib.op_type_id = ANY(_filter)) AND
          (_first_key OR jsonb_extract_path_text(oib.body, variadic ARRAY(SELECT json_array_elements_text(_setof_keys->0))) = _key_content[1]) AND
          (_second_key OR jsonb_extract_path_text(oib.body, variadic ARRAY(SELECT json_array_elements_text(_setof_keys->1))) = _key_content[2]) AND
          (_third_key OR jsonb_extract_path_text(oib.body, variadic ARRAY(SELECT json_array_elements_text(_setof_keys->2))) = _key_content[3])
      )
      SELECT * FROM filter_ops fo
      ORDER BY
        (CASE WHEN _order_is = 'desc' THEN fo.id ELSE NULL END) DESC,
        (CASE WHEN _order_is = 'asc' THEN fo.id ELSE NULL END) ASC
      LIMIT _page_size
      OFFSET _offset
    ) ls
    JOIN hive.operation_types hot ON hot.id = ls.op_type_id
    LEFT JOIN hive.transactions_view htv ON htv.block_num = ls.block_num AND htv.trx_in_block = ls.trx_in_block
    ORDER BY
      (CASE WHEN _order_is = 'desc' THEN ls.id ELSE NULL END) DESC,
      (CASE WHEN _order_is = 'asc' THEN ls.id ELSE NULL END) ASC)

  -- filter too long operation bodies 
    SELECT filtered_operations.id::TEXT, filtered_operations.block_num, filtered_operations.trx_in_block, filtered_operations.trx_hash, filtered_operations.op_pos, filtered_operations.op_type_id,
    (filtered_operations.composite).body, filtered_operations.is_virtual, filtered_operations.timestamp, filtered_operations.age, (filtered_operations.composite).is_modified
    FROM (
    SELECT hafbe_backend.operation_body_filter(opr.body, opr.id, _body_limit) as composite, opr.id, opr.block_num, opr.trx_in_block, opr.trx_hash, opr.op_pos, opr.op_type_id, opr.is_virtual, hb.created_at timestamp, NOW() - hb.created_at AS age
    FROM operation_range opr
    JOIN hive.blocks_view hb ON hb.num = opr.block_num
    ) filtered_operations
    ORDER BY filtered_operations.id, filtered_operations.trx_in_block, filtered_operations.op_pos;

END IF;

END
$$;


CREATE OR REPLACE FUNCTION hafbe_backend.get_ops_by_block_count(
    _block_num INT,
    _filter INT [],
    _account TEXT,
    _key_content TEXT [],
    _setof_keys JSON
)
RETURNS INT -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
SET JIT = OFF
SET join_collapse_limit = 16
SET from_collapse_limit = 16
AS
$$
DECLARE
  __no_ops_filter BOOLEAN = (_filter IS NULL);
  _first_key BOOLEAN = (_key_content[1] IS NULL);
  _second_key BOOLEAN = (_key_content[2] IS NULL);
  _third_key BOOLEAN = (_key_content[3] IS NULL);
BEGIN

IF _account IS NULL THEN
  RETURN (
    WITH operations_in_block AS 
    (
      SELECT ov.op_type_id, ov.body
      FROM hive.operations_view ov
      WHERE
        ov.block_num = _block_num 
    ),
    filter_ops AS MATERIALIZED 
    (
      SELECT oib.op_type_id 
      FROM operations_in_block oib 
      WHERE 
        (__no_ops_filter OR oib.op_type_id = ANY(_filter)) AND
        (_first_key OR jsonb_extract_path_text(oib.body, variadic ARRAY(SELECT json_array_elements_text(_setof_keys->0))) = _key_content[1]) AND
        (_second_key OR jsonb_extract_path_text(oib.body, variadic ARRAY(SELECT json_array_elements_text(_setof_keys->1))) = _key_content[2]) AND
        (_third_key OR jsonb_extract_path_text(oib.body, variadic ARRAY(SELECT json_array_elements_text(_setof_keys->2))) = _key_content[3])
    )
    SELECT COUNT(*) FROM filter_ops);
ELSE
  RETURN (
    WITH account_operations_in_block AS 
    (
      SELECT aov.operation_id
      FROM hive.account_operations_view aov
      WHERE
        aov.account_id = (SELECT av.id FROM hive.accounts_view av WHERE av.name = _account ) AND
        aov.block_num = _block_num 
    ),
    operations_in_block AS 
    (
      SELECT ov.op_type_id, ov.body
      FROM hive.operations_view ov
      JOIN account_operations_in_block aoib ON aoib.operation_id = ov.id
    ),
    filter_ops AS MATERIALIZED 
    (
      SELECT oib.op_type_id 
      FROM operations_in_block oib 
      WHERE 
        (__no_ops_filter OR oib.op_type_id = ANY(_filter)) AND
        (_first_key OR jsonb_extract_path_text(oib.body, variadic ARRAY(SELECT json_array_elements_text(_setof_keys->0))) = _key_content[1]) AND
        (_second_key OR jsonb_extract_path_text(oib.body, variadic ARRAY(SELECT json_array_elements_text(_setof_keys->1))) = _key_content[2]) AND
        (_third_key OR jsonb_extract_path_text(oib.body, variadic ARRAY(SELECT json_array_elements_text(_setof_keys->2))) = _key_content[3])
    )
    SELECT COUNT(*) FROM filter_ops);

END IF;

END
$$;

RESET ROLE;
