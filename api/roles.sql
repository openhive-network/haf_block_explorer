-- recreate hafbe schemas owner
DROP ROLE IF EXISTS hafbe_owner;
CREATE ROLE hafbe_owner LOGIN INHERIT IN ROLE hive_applications_group;
GRANT hafbe_owner TO hive;

ALTER SCHEMA hafbe_backend OWNER TO hafbe_owner;
ALTER SCHEMA hafbe_endpoints OWNER TO hafbe_owner;
ALTER SCHEMA hafbe_exceptions OWNER TO hafbe_owner;

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
GRANT hafbe_user TO hive;

-- grant new priviliges
GRANT USAGE ON SCHEMA hafbe_backend TO hafbe_user;
GRANT USAGE ON SCHEMA hafbe_endpoints TO hafbe_user;
GRANT USAGE ON SCHEMA hafbe_exceptions TO hafbe_user;

GRANT USAGE ON SCHEMA btracker_app TO hafbe_user;
GRANT USAGE ON SCHEMA hafah_python TO hafbe_user;
GRANT USAGE ON SCHEMA hive TO hafbe_user;