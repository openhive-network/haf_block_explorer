-- Role involved into data schema creation.
DO $$
BEGIN
  CREATE ROLE hafbe_owner WITH LOGIN INHERIT IN ROLE hive_applications_group;

  CREATE ROLE hafbe_user WITH LOGIN INHERIT IN ROLE hive_applications_group;
  
EXCEPTION WHEN duplicate_object THEN RAISE NOTICE '%, skipping', SQLERRM USING ERRCODE = SQLSTATE;
END
$$;


