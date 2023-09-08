CREATE OR REPLACE FUNCTION hafbe_backend.get_account_id(_account TEXT)
RETURNS INT STABLE
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN id FROM hive.accounts_view WHERE name = _account;
END
$$
;

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

  RETURN __profile_image_url;
END
$$
;

--ACCOUNT LAST POST TIME

DROP TYPE IF EXISTS hafbe_backend.last_post_vote_time CASCADE;
CREATE TYPE hafbe_backend.last_post_vote_time AS
(
  last_post TIMESTAMP,
  last_root_post TIMESTAMP,
  last_vote_time TIMESTAMP,
  post_count INT
);

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
  RETURN __result;

END
$$
;


CREATE OR REPLACE FUNCTION hafbe_backend.get_account_proxy(_account INT)
RETURNS TEXT
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE 
_result TEXT := (SELECT a.name FROM hafbe_app.current_account_proxies o
JOIN hive.accounts_view a on a.id = o.proxy_id
WHERE o.account_id = _account);
BEGIN

RETURN _result;

END
$$
;


--ACCOUNT can_vote, mined, created, recovery

DROP TYPE IF EXISTS hafbe_backend.account_parameters CASCADE;
CREATE TYPE hafbe_backend.account_parameters AS
(
  can_vote BOOLEAN,
  mined BOOLEAN,
  recovery_account TEXT,
  last_account_recovery TIMESTAMP,
  created TIMESTAMP
);

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
  RETURN __result;

END
$$
;

--ACCOUNT can_vote, mined, created, recovery

DROP TYPE IF EXISTS hafbe_backend.account_votes CASCADE;
CREATE TYPE hafbe_backend.account_votes AS
(
  proxied_vsf_votes JSON,
  witnesses_voted_for INT,
  witness_votes JSON
);

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

  RETURN __result;

END
$$
;

--ACCOUNT METADATA

DROP TYPE IF EXISTS hafbe_backend.json_metadata CASCADE;
CREATE TYPE hafbe_backend.json_metadata AS
(
  json_metadata TEXT,
  posting_json_metadata TEXT
);

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
  RETURN __result;
END
$$
;

--ACCOUNT KEYAUTH

DROP TYPE IF EXISTS hafbe_backend.account_keyauth CASCADE;
CREATE TYPE hafbe_backend.account_keyauth AS
(
  key_auth TEXT,
  authority_kind hive.authority_type
);

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
ORDER BY authority_kind ASC;

END
$$
;

