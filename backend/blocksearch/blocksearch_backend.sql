SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_backend.get_producer_reward(_block_num INT)
RETURNS BIGINT
LANGUAGE 'plpgsql'
STABLE
AS
$$
BEGIN
RETURN (ov.body->'value'->'vesting_shares'->>'amount')::BIGINT
FROM hive.operations_view ov
WHERE	
  ov.block_num = _block_num AND 
	ov.op_type_id = 64;
END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.get_block_operation_aggregation(_block_num INT)
RETURNS JSON
LANGUAGE 'plpgsql'
STABLE
AS
$$
BEGIN
RETURN 
  json_agg(
    json_build_object(
      'op_type_id', op_type_id,
      'op_count', op_count
    )
	)
FROM hafbe_app.block_operations
WHERE	block_num = _block_num;
END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.build_json_for_single_operation(_op_type_id INT, _op_count INT)
RETURNS JSON
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
BEGIN
RETURN 
  json_build_array(
    json_build_object(
          'op_type_id', _op_type_id,
          'op_count', _op_count
        )
  ) AS operations;
END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.get_trx_count(_block_num INT)
RETURNS INT
LANGUAGE 'plpgsql'
STABLE
AS
$$
BEGIN
RETURN COUNT(*)
FROM hive.transactions_view
WHERE	block_num = _block_num;
END
$$;

DROP TYPE IF EXISTS hafbe_backend.blocksearch_filter_return CASCADE;
CREATE TYPE hafbe_backend.blocksearch_filter_return AS
(
    count_blocks INT,
    from_block INT,
    to_block INT
);

CREATE OR REPLACE FUNCTION hafbe_backend.blocksearch_no_filter_count(
    _from INT, 
    _to INT,
    _current_block INT
)
RETURNS hafbe_backend.blocksearch_filter_return -- noqa: LT01, CP05
LANGUAGE 'plpgsql' IMMUTABLE
SET JIT = OFF
AS
$$
DECLARE 
  __to INT;
  __from INT;
  __count INT;
BEGIN
  __to := (
    CASE 
      WHEN (_to IS NULL) THEN 
        _current_block 
      WHEN (_to IS NOT NULL) AND (_current_block < _to) THEN 
        _current_block 
      ELSE 
        _to 
      END
  );

  __from := (
    CASE 
      WHEN (_from IS NULL) THEN 
        1 
      ELSE 
        _from 
      END
  );

  __count := __to - __from + 1;

  RETURN (__count, __from, __to)::hafbe_backend.blocksearch_filter_return;
END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.blocksearch_range(
    _from INT, 
    _to INT,
    _current_block INT
)
RETURNS hafbe_backend.blocksearch_filter_return -- noqa: LT01, CP05
LANGUAGE 'plpgsql' IMMUTABLE
SET JIT = OFF
AS
$$
DECLARE 
  __to INT;
  __from INT;
BEGIN
  __to := (
    CASE 
      WHEN (_to IS NULL) THEN 
        _current_block 
      WHEN (_to IS NOT NULL) AND (_current_block < _to) THEN 
        _current_block 
      ELSE 
        _to 
      END
  );

  __from := (
    CASE 
      WHEN (_from IS NULL) THEN 
        1 
      ELSE 
        _from 
      END
  );

  RETURN (NULL, __from, __to)::hafbe_backend.blocksearch_filter_return;
END
$$;

DROP TYPE IF EXISTS hafbe_backend.blocksearch_account_filter_return CASCADE;
CREATE TYPE hafbe_backend.blocksearch_account_filter_return AS
(
    from_block INT,
    to_block INT,
    from_seq INT,
    to_seq INT
);

CREATE OR REPLACE FUNCTION hafbe_backend.blocksearch_account_range(
    _account_id INT,
    _from INT, 
    _to INT,
    _current_block INT
)
RETURNS hafbe_backend.blocksearch_account_filter_return -- noqa: LT01, CP05
LANGUAGE 'plpgsql' IMMUTABLE
SET JIT = OFF
AS
$$
DECLARE 
  __to INT;
  __from INT;
  __to_seq INT;
  __from_seq INT;
BEGIN
  __to := (
    CASE 
      WHEN (_to IS NULL) THEN 
        _current_block 
      WHEN (_to IS NOT NULL) AND (_current_block < _to) THEN 
        _current_block 
      ELSE 
        _to 
      END
  );

  __from := (
    CASE 
      WHEN (_from IS NULL) THEN 
        1 
      ELSE 
        _from 
      END
  );

  __to_seq := (
    SELECT 
      aov.account_op_seq_no
    FROM hive.account_operations_view aov
    WHERE 
      aov.account_id = _account_id AND
      aov.block_num <= __to
    ORDER BY aov.account_op_seq_no DESC LIMIT 1
  );

  __from_seq := (
    SELECT 
      aov.account_op_seq_no
    FROM hive.account_operations_view aov
    WHERE 
      aov.account_id = _account_id AND
      aov.block_num >= __from
    ORDER BY aov.account_op_seq_no ASC LIMIT 1
  );


  RETURN (__from, __to, __from_seq, __to_seq)::hafbe_backend.blocksearch_account_filter_return;
END
$$;


CREATE OR REPLACE FUNCTION hafbe_backend.blocksearch_by_op_count(
    _operation INT,
    _from INT, 
    _to INT,
    _current_block INT,
    _order_is hafbe_types.sort_direction, -- noqa: LT01, CP05
    _limit INT
)
RETURNS hafbe_backend.blocksearch_filter_return -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET JIT = OFF
AS
$$
DECLARE 
  __to INT;
  __from INT;
BEGIN
  __to := (
    CASE 
      WHEN (_to IS NULL) THEN 
        _current_block 
      WHEN (_to IS NOT NULL) AND (_current_block < _to) THEN 
        _current_block 
      ELSE 
        _to 
      END
  );

  __from := (
    CASE 
      WHEN (_from IS NULL) THEN 
        1 
      ELSE 
        _from 
      END
  );

  RETURN (
    WITH blocks AS (
      SELECT 
        COUNT(*) AS count_blocks
      FROM (
        SELECT *
        FROM hafbe_app.block_operations ov
        WHERE 
          ov.op_type_id = _operation AND
          ov.block_num <= __to AND
          ov.block_num >= __from
        ORDER BY
          (CASE WHEN _order_is = 'desc' THEN ov.block_num ELSE NULL END) DESC,
          (CASE WHEN _order_is = 'asc' THEN ov.block_num ELSE NULL END) ASC
        LIMIT (10 * _limit) -- by default operation filter is limited to 10 pages
      )
    )
    SELECT (
      count_blocks,
      __from,
      __to
    )::hafbe_backend.blocksearch_filter_return
    FROM blocks
  );
END
$$;

DROP TYPE IF EXISTS hafbe_backend.calculate_pages_return CASCADE;
CREATE TYPE hafbe_backend.calculate_pages_return AS
(
    rest_of_division INT,
    total_pages INT,
    page_num INT,
    offset_filter INT,
    limit_filter INT
);

CREATE OR REPLACE FUNCTION hafbe_backend.blocksearch_calculate_pages(
    _count INT,
    _page INT,
    _order_is hafbe_types.sort_direction, -- noqa: LT01, CP05
    _limit INT
)
RETURNS hafbe_backend.calculate_pages_return -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
SET JIT = OFF
AS
$$
DECLARE 
  __rest_of_division INT;
  __total_pages INT;
  __page INT;
  __offset INT;
  __limit INT;
BEGIN
  __rest_of_division := (_count % _limit)::INT;

  __total_pages := (
    CASE 
      WHEN (__rest_of_division = 0) THEN 
        _count / _limit 
      ELSE 
        (_count / _limit) + 1
      END
  )::INT;

  __page := (
    CASE 
      WHEN (_page IS NULL) THEN 
        1
      WHEN (_page IS NOT NULL) AND _order_is = 'desc' THEN 
        __total_pages - _page + 1
      ELSE 
        _page 
      END
  );

  __offset := (
    CASE
      WHEN _order_is = 'desc' AND __page != 1 AND __rest_of_division != 0 THEN 
        ((__page - 2) * _limit) + __rest_of_division
      WHEN __page = 1 THEN 
        0
      ELSE
        (__page - 1) * _limit
      END
    );

  __limit := (
      CASE
        WHEN _order_is = 'desc' AND __page = 1             AND __rest_of_division != 0 THEN
          __rest_of_division 
        WHEN _order_is = 'asc'  AND __page = __total_pages AND __rest_of_division != 0 THEN
          __rest_of_division 
        ELSE 
          _limit 
        END
    );

  PERFORM hafah_python.validate_page(_page, __total_pages);

  RETURN (__rest_of_division, __total_pages, __page, __offset, __limit)::hafbe_backend.calculate_pages_return;
END
$$;

DROP TYPE IF EXISTS hafbe_backend.find_blocks_with_op_return CASCADE;
CREATE TYPE hafbe_backend.find_blocks_with_op_return AS
(
    block_num INT,
    op_type_id INT,
    op_count INT
);

CREATE OR REPLACE FUNCTION hafbe_backend.find_blocks_with_op(
    _operation INT,
    _from INT, 
    _to INT,
    _order_is hafbe_types.sort_direction, -- noqa: LT01, CP05
    _limit INT
)
RETURNS SETOF hafbe_backend.find_blocks_with_op_return -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET JIT = OFF
AS
$$
BEGIN
  RETURN QUERY (
    SELECT 
      bo.block_num,
      bo.op_type_id,
      bo.op_count
    FROM hafbe_app.block_operations bo
    WHERE
      bo.op_type_id = _operation AND
      bo.block_num >= _from AND
      bo.block_num <= _to
    ORDER BY
      (CASE WHEN _order_is = 'desc' THEN bo.block_num ELSE NULL END) DESC,
      (CASE WHEN _order_is = 'asc' THEN bo.block_num ELSE NULL END) ASC
    LIMIT _limit -- by default multi operation filter is limited to 1 page per operation
  );
END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.find_blocks_with_op_and_account(
    _operation INT,
    _account_id INT,
    _from INT, 
    _to INT,
    _order_is hafbe_types.sort_direction, -- noqa: LT01, CP05
    _limit INT
)
RETURNS SETOF hafbe_backend.find_blocks_with_op_return -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET JIT = OFF
AS
$$
BEGIN
  RETURN QUERY (
    SELECT 
      aov.block_num,
      aov.op_type_id,
      NULL::int
    FROM hive.account_operations_view aov
    WHERE 
	    aov.op_type_id = _operation AND
      aov.account_id = _account_id AND
      aov.block_num >= _from AND
      aov.block_num <= _to
    ORDER BY
      (CASE WHEN _order_is = 'desc' THEN aov.block_num ELSE NULL END) DESC,
      (CASE WHEN _order_is = 'asc' THEN aov.block_num ELSE NULL END) ASC
    LIMIT _limit -- by default multi operation filter is limited to 1 page per operation
  );
END
$$;

RESET ROLE;
