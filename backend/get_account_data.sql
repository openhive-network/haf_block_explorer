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
DECLARE
  __result hafbe_backend.last_post_vote_time;
BEGIN
SELECT last_post, last_root_post, last_vote_time, post_count 
INTO __result
FROM hafbe_app.account_posts WHERE account= _account;
RETURN __result
;

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
DECLARE 
_result INT := (SELECT (account_op_seq_no + 1) FROM hive.account_operations_view where account_id = _account  order by account_op_seq_no DESC limit 1);
BEGIN
RETURN _result
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
DECLARE 
  _result TEXT := (SELECT a.name FROM hafbe_app.current_account_proxies o JOIN hive.accounts_view a on a.id = o.proxy_id WHERE o.account_id = _account);
BEGIN
RETURN _result
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
DECLARE
  __result hafbe_backend.account_parameters;
BEGIN
SELECT can_vote, mined, recovery_account, last_account_recovery, created
INTO __result
FROM hafbe_app.account_parameters WHERE account= _account;
RETURN __result
;

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
DECLARE
  __result hafbe_backend.account_votes;
BEGIN
SELECT json_agg(vote), COUNT(*)
INTO __result.witness_votes, __result.witnesses_voted_for
FROM hafbe_views.current_witness_votes_view WHERE account= _account;

With selected_poxied_vests AS (
  SELECT proxied_vests, which_proxy FROM hafbe_views.voters_proxied_vests_view WHERE proxy_id= _account
)

SELECT json_agg(
  proxied_vests
) INTO __result.proxied_vsf_votes
FROM hafbe_views.voters_proxied_vests_view WHERE proxy_id= _account;

RETURN __result
;

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
DECLARE
  __result hafbe_backend.json_metadata;
BEGIN
SELECT json_metadata, posting_json_metadata 
INTO __result
FROM hive.hafbe_app_metadata WHERE account_id= _account;
RETURN __result
;

END
$$
;

-- ACCOUNT KEYAUTHS
CREATE OR REPLACE FUNCTION hafbe_backend.get_account_keyauth(_account TEXT)
RETURNS SETOF hafbe_backend.account_keyauth
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
BEGIN
RETURN QUERY SELECT key_auth, authority_kind 
FROM hive.hafbe_app_keyauth 
WHERE account_name= _account 
ORDER BY authority_kind ASC
;

END
$$
;

RESET ROLE;
