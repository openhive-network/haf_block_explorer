-- Functions used in hafbe_endpoints.get_account

SET ROLE hafbe_owner;

-- ACCOUNT ID
CREATE OR REPLACE FUNCTION hafbe_backend.get_account_id(_account TEXT)
RETURNS INT STABLE
LANGUAGE 'plpgsql'
AS
$$
BEGIN
RETURN 
  av.id 
FROM hive.accounts_view av WHERE av.name = _account
;

END
$$;

-- ACCOUNT PROFILE PICTURE
CREATE OR REPLACE FUNCTION hafbe_backend.parse_profile_picture(json_metadata TEXT, posting_json_metadata TEXT)
RETURNS TEXT IMMUTABLE
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __profile_image_url TEXT;
BEGIN
BEGIN
  SELECT json_metadata::JSON->'profile'->>'profile_image' INTO __profile_image_url;
EXCEPTION WHEN invalid_text_representation THEN
  SELECT NULL INTO __profile_image_url;
END;

IF __profile_image_url IS NULL THEN 
BEGIN
  SELECT posting_json_metadata::JSON->'profile'->>'profile_image' INTO __profile_image_url;
EXCEPTION WHEN invalid_text_representation THEN
  SELECT NULL INTO __profile_image_url;
END;
END IF;

RETURN __profile_image_url
;

END
$$;

-- ACCOUNT POST COUNT
CREATE OR REPLACE FUNCTION hafbe_backend.get_account_ops_count(_account INT)
RETURNS INT
LANGUAGE 'plpgsql'
STABLE
AS
$$
BEGIN
RETURN aov.account_op_seq_no + 1
FROM hive.account_operations_view aov
WHERE aov.account_id = _account 
ORDER BY aov.account_op_seq_no DESC LIMIT 1
;

END
$$;

-- ACCOUNT PROXY
CREATE OR REPLACE FUNCTION hafbe_backend.get_account_proxy(_account INT)
RETURNS TEXT
LANGUAGE 'plpgsql'
STABLE
AS
$$
BEGIN
RETURN 
(SELECT av.name FROM hive.accounts_view av WHERE av.id = cap.proxy_id)
FROM hafbe_app.current_account_proxies cap
WHERE cap.account_id = _account
;

END
$$;

-- ACCOUNT PARAMETERS
CREATE OR REPLACE FUNCTION hafbe_backend.get_account_parameters(_account INT)
RETURNS hafbe_backend.account_parameters -- noqa: LT01, CP05
LANGUAGE 'plpgsql'
STABLE
AS
$$
BEGIN
RETURN (
  SELECT ROW (ap.can_vote, ap.mined, ap.recovery_account, ap.last_account_recovery, ap.created)
  FROM hafbe_app.account_parameters ap
  WHERE ap.account = _account
);

END
$$;

-- ACCOUNT VOTES
CREATE OR REPLACE FUNCTION hafbe_backend.get_account_witness_votes(_account INT)
RETURNS hafbe_backend.account_votes -- noqa: LT01, CP05
LANGUAGE 'plpgsql'
STABLE
AS
$$
BEGIN
RETURN (
  SELECT ROW(
    (SELECT json_agg(vpvv.proxied_vests) FROM hafbe_views.voters_proxied_vests_view vpvv WHERE vpvv.proxy_id= _account), 
    COUNT(*)::INT, 
    json_agg(cwvv.vote))
  FROM hafbe_views.current_witness_votes_view cwvv WHERE cwvv.account = _account
);

END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.get_account_last_vote(_account INT)
RETURNS timestamp -- noqa: LT01, CP05
LANGUAGE 'plpgsql'
STABLE
AS
$$
BEGIN
RETURN ov.timestamp 
FROM hive.account_operations aov 
JOIN hive.operations ov ON ov.id = aov.operation_id 
WHERE aov.op_type_id = 72 
AND aov.account_id = _account 
AND ov.body_binary::JSONB->'value'->>'voter'= (SELECT av.name FROM hive.accounts_view av WHERE av.id = _account)
ORDER BY account_op_seq_no DESC
LIMIT 1;

END
$$;

-- ACCOUNT METADATA
CREATE OR REPLACE FUNCTION hafbe_backend.get_json_metadata(_account INT)
RETURNS hafbe_backend.json_metadata -- noqa: LT01, CP05
LANGUAGE 'plpgsql'
STABLE
AS
$$
BEGIN
RETURN (SELECT ROW (
  m.json_metadata, 
  m.posting_json_metadata)
FROM hive.hafbe_app_metadata m
WHERE m.account_id = _account
);

END
$$;

RESET ROLE;
