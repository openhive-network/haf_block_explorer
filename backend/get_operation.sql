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
    _operations INT [],
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
    o.op_type_id = ANY(_operations) AND 
    o.body_binary::jsonb->'value'->>'author' = _author AND
    (CASE WHEN _permlink IS NOT NULL THEN
    o.body_binary::jsonb->'value'->>'permlink' = _permlink ELSE
    TRUE END)
  ORDER BY author, permlink, o.id
  LIMIT 100
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
    _operations INT [],
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
    o.op_type_id = ANY(_operations) AND 
    o.body_binary::jsonb->'value'->>'author' = _author AND
    (CASE WHEN _permlink IS NOT NULL THEN
    o.body_binary::jsonb->'value'->>'permlink' = _permlink ELSE
    TRUE
    END));

END
$$;


RESET ROLE;
