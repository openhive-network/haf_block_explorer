-- Functions used in hafbe_endpoints.get_account

SET ROLE hafbe_owner;

-- ACCOUNT ID
CREATE OR REPLACE FUNCTION hafbe_backend.get_account_id(_account TEXT)
RETURNS INT STABLE
LANGUAGE 'plpgsql'
AS
$$
BEGIN
RETURN id FROM hive.accounts_view WHERE name = _account
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
RETURN account_op_seq_no + 1
FROM hive.account_operations_view 
WHERE account_id = _account ORDER BY account_op_seq_no DESC LIMIT 1
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
RETURN a.name 
FROM hafbe_app.current_account_proxies o 
JOIN hive.accounts_view a on a.id = o.proxy_id 
WHERE o.account_id = _account
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
RETURN (SELECT ROW (can_vote, mined, recovery_account, last_account_recovery, created)
FROM hafbe_app.account_parameters WHERE account= _account
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
RETURN (SELECT ROW(
  (SELECT json_agg(proxied_vests) FROM hafbe_views.voters_proxied_vests_view WHERE proxy_id= _account), 
  COUNT(1)::INT, 
  json_agg(vote))
FROM hafbe_views.current_witness_votes_view WHERE account= _account
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
RETURN vv.timestamp FROM hafbe_views.votes_view vv 
WHERE vv.voter = (SELECT a.name FROM hive.accounts_view a WHERE a.id = _account) order by vv.block_num DESC LIMIT 1;

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
  json_metadata, 
  posting_json_metadata)
FROM hive.hafbe_app_metadata 
WHERE account_id= _account
);

END
$$;


CREATE OR REPLACE FUNCTION hafbe_backend.get_account_authorizations(
    _account TEXT,
    _key_kind hive.key_type -- noqa: LT01, CP05
)
RETURNS hafbe_backend.account_authorizations -- noqa: LT01, CP05
LANGUAGE 'plpgsql'
STABLE
SET JIT = OFF
SET join_collapse_limit = 16
SET from_collapse_limit = 16
AS
$$
BEGIN
RETURN (
    COALESCE(
    (
      WITH get_key_auth AS (
      SELECT ARRAY[hive.public_key_to_string(keys.key), active_key_auths.w::TEXT] as key_auth
      FROM hive.hafbe_app_keyauth_a active_key_auths
      JOIN hive.hafbe_app_keyauth_k keys ON active_key_auths.key_serial_id = keys.key_id
      WHERE active_key_auths.account_id = (SELECT get_account_id FROM hafbe_backend.get_account_id(_account)) 
      AND active_key_auths.key_kind = _key_kind
      AND (active_key_auths.key_kind != 'MEMO' OR active_key_auths.key_kind != 'WITNESS_SIGNING'))

      SELECT array_agg(gka.key_auth) AS key_auth
      FROM get_key_auth gka
    ), '{}'
  ),

    COALESCE(
    (
      WITH get_account_auth AS (
      SELECT ARRAY[av.name, active_account_auths.w::TEXT] AS key_auth
      FROM hive.hafbe_app_accountauth_a active_account_auths
      JOIN hive.accounts_view av ON active_account_auths.account_auth_id = av.id
      WHERE active_account_auths.account_id = (SELECT get_account_id FROM hafbe_backend.get_account_id(_account))
      AND active_account_auths.key_kind = _key_kind)

      SELECT array_agg(gaa.key_auth) 
      FROM get_account_auth gaa 
    ), '{}'
  )::TEXT[]
);

END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.get_account_memo(
    _account TEXT
)
RETURNS TEXT -- noqa: LT01, CP05
LANGUAGE 'plpgsql'
STABLE
SET JIT = OFF
SET join_collapse_limit = 16
SET from_collapse_limit = 16
AS
$$
BEGIN
RETURN (
  COALESCE(
    (
      SELECT hive.public_key_to_string(keys.key) as key_auth
      FROM hive.hafbe_app_keyauth_a active_key_auths
      JOIN hive.hafbe_app_keyauth_k keys ON active_key_auths.key_serial_id = keys.key_id
      WHERE active_key_auths.account_id = (SELECT get_account_id FROM hafbe_backend.get_account_id(_account)) 
      AND active_key_auths.key_kind = 'MEMO'
    ), ''
  )
);

END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.get_account_witness_singing(
    _account TEXT
)
RETURNS TEXT -- noqa: LT01, CP05
LANGUAGE 'plpgsql'
STABLE
SET JIT = OFF
SET join_collapse_limit = 16
SET from_collapse_limit = 16
AS
$$
BEGIN
RETURN (
  COALESCE(
    (
      SELECT hive.public_key_to_string(keys.key) as key_auth
      FROM hive.hafbe_app_keyauth_a active_key_auths
      JOIN hive.hafbe_app_keyauth_k keys ON active_key_auths.key_serial_id = keys.key_id
      WHERE active_key_auths.account_id = (SELECT get_account_id FROM hafbe_backend.get_account_id(_account)) 
      AND active_key_auths.key_kind = 'WITNESS_SIGNING'
    ), ''
  )
);

END
$$;

RESET ROLE;
