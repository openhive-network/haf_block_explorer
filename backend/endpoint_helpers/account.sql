SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_backend.get_account_proxied_vsf_votes(_account INT)
RETURNS TEXT[] -- noqa: LT01, CP05
LANGUAGE 'plpgsql'
STABLE
AS
$$
BEGIN
RETURN (
  WITH proxy_levels AS MATERIALIZED
  (
    SELECT 
      vpvv.proxied_vests as proxy, 
      vpvv.proxy_level 
    FROM hafbe_views.voters_proxied_vests_view vpvv 
    WHERE 
      vpvv.proxy_id= _account
    ORDER BY vpvv.proxy_level 
  ),
  populate_record AS MATERIALIZED
  (
    SELECT '0' as proxy, 1 as proxy_level
    UNION ALL
    SELECT '0' as proxy, 2 as proxy_level
    UNION ALL
    SELECT '0' as proxy, 3 as proxy_level
    UNION ALL
    SELECT '0' as proxy, 4 as proxy_level
  )
  SELECT 
    array_agg(coalesce(s.proxy::TEXT,pr.proxy) ORDER BY pr.proxy_level) 
  FROM populate_record pr
  LEFT JOIN proxy_levels s ON s.proxy_level = pr.proxy_level
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
    COUNT(*)::INT, 
    array_agg(cwvv.vote)
  )::hafbe_backend.account_votes
  FROM hafbe_views.current_witness_votes_view cwvv 
  WHERE cwvv.account = _account;
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
  ORDER BY aov.account_op_seq_no DESC LIMIT 1;
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
  WHERE cap.account_id = _account;
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
  SELECT ROW (ap.can_vote, ap.mined, ap.recovery_account, ap.last_account_recovery, ap.created, ap.pending_claimed_accounts)
  FROM hafbe_app.account_parameters ap
  WHERE ap.account = _account
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
  FROM hive.account_operations_view aov
  JOIN hive.operations_view_extended ov ON ov.id = aov.operation_id
  WHERE aov.op_type_id = 72 AND
    aov.account_id = _account AND
    ov.body_binary::JSONB->'value'->>'voter'= (SELECT av.name FROM hive.accounts_view av WHERE av.id = _account)
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
RETURN (
  SELECT ROW(
    m.json_metadata, 
    m.posting_json_metadata
  )
  FROM hafd.hafbe_app_metadata m
  WHERE m.account_id = _account
);

END
$$;

RESET ROLE;
