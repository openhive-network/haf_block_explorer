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
$$
;

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
$$
;

-- ACCOUNT POST DATES
CREATE OR REPLACE FUNCTION hafbe_backend.get_last_post_vote_time(_account INT)
RETURNS hafbe_backend.last_post_vote_time
LANGUAGE 'plpgsql'
STABLE
AS
$$
BEGIN
RETURN (SELECT ROW( last_post, last_root_post, last_vote_time, post_count)
FROM hafbe_app.account_posts 
WHERE account= _account
);

END
$$
;

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
$$
;

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
$$
;

-- ACCOUNT PARAMETERS
CREATE OR REPLACE FUNCTION hafbe_backend.get_account_parameters(_account INT)
RETURNS hafbe_backend.account_parameters
LANGUAGE 'plpgsql'
STABLE
AS
$$
BEGIN
RETURN (SELECT ROW (can_vote, mined, recovery_account, last_account_recovery, created)
FROM hafbe_app.account_parameters WHERE account= _account
);

END
$$
;

-- ACCOUNT VOTES
CREATE OR REPLACE FUNCTION hafbe_backend.get_account_votes(_account INT)
RETURNS hafbe_backend.account_votes
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
$$
;

-- ACCOUNT METADATA
CREATE OR REPLACE FUNCTION hafbe_backend.get_json_metadata(_account INT)
RETURNS hafbe_backend.json_metadata
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
$$
;


RESET ROLE;
