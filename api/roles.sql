-- drop priviliges of schemas user
DO $$
BEGIN
  IF (SELECT rolname FROM pg_roles WHERE rolname='hafbe_user') IS NOT NULL THEN
    DROP OWNED BY hafbe_user CASCADE;
  END IF;
END
$$
;

-- recreate hafbe schemas user
DROP ROLE IF EXISTS hafbe_user;
CREATE ROLE hafbe_user LOGIN INHERIT IN ROLE hive_applications_group;

-- grant new priviliges
GRANT USAGE ON SCHEMA hafbe_backend TO hafbe_user;
GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA hafbe_backend TO hafbe_user;

GRANT USAGE ON SCHEMA hafbe_endpoints TO hafbe_user;
GRANT SELECT ON ALL TABLES IN SCHEMA hafbe_endpoints TO hafbe_user;

GRANT USAGE ON SCHEMA hafbe_exceptions TO hafbe_user;
GRANT SELECT ON ALL TABLES IN SCHEMA hafbe_exceptions TO hafbe_user;

GRANT USAGE ON SCHEMA hafbe_views TO hafbe_user;
GRANT SELECT ON ALL TABLES IN SCHEMA hafbe_views TO hafbe_user;

GRANT USAGE ON SCHEMA hafbe_types TO hafbe_user;
GRANT SELECT ON ALL TABLES IN SCHEMA hafbe_types TO hafbe_user;

GRANT USAGE ON SCHEMA btracker_app TO hafbe_user;
GRANT SELECT ON ALL TABLES IN SCHEMA btracker_app TO hafbe_user;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA btracker_app TO hafbe_user;

GRANT USAGE ON SCHEMA hafah_python TO hafbe_user;
GRANT SELECT ON ALL TABLES IN SCHEMA hafah_python TO hafbe_user;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA hafah_python TO hafbe_user;

GRANT USAGE ON SCHEMA hive TO hafbe_user;
GRANT SELECT ON ALL TABLES IN SCHEMA hive TO hafbe_user;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA hive TO hafbe_user;

GRANT USAGE ON SCHEMA hafbe_app TO hafbe_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hafbe_app TO hafbe_user;
GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA hafbe_app TO hafbe_user;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA hafbe_app TO hafbe_user;

-- plpython3u must be trusted language
GRANT USAGE ON LANGUAGE plpython3u TO hafbe_owner;