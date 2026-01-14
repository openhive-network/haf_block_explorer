-- Role involved into data schema creation.
DO $$
BEGIN
  CREATE ROLE hafbe_owner WITH LOGIN INHERIT IN ROLE hive_applications_owner_group, reptracker_owner, btracker_owner, hafah_owner;
EXCEPTION WHEN duplicate_object THEN RAISE NOTICE '%, skipping', SQLERRM USING ERRCODE = SQLSTATE;
END
$$;

DO $$
BEGIN
  CREATE ROLE hafbe_user WITH LOGIN INHERIT IN ROLE hive_applications_group, reptracker_user, btracker_user, hafah_user;  
EXCEPTION WHEN duplicate_object THEN RAISE NOTICE '%, skipping', SQLERRM USING ERRCODE = SQLSTATE;
END
$$;
