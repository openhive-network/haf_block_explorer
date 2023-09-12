-- Role involved into data schema creation.
DO $$
BEGIN
  CREATE ROLE hafbe_owner WITH LOGIN INHERIT IN ROLE hive_applications_group;

  CREATE ROLE hafbe_user WITH LOGIN INHERIT IN ROLE hive_applications_group;
  
EXCEPTION WHEN duplicate_object THEN RAISE NOTICE '%, skipping', SQLERRM USING ERRCODE = SQLSTATE;
END
$$;

GRANT btracker_owner TO hafbe_owner;
GRANT btracker_user TO hafbe_owner;
GRANT ALL ON SCHEMA btracker_app TO hafbe_owner;