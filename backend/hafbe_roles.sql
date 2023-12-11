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

GRANT USAGE ON SCHEMA btracker_endpoints TO hafbe_user;
GRANT SELECT ON ALL TABLES IN SCHEMA btracker_endpoints TO hafbe_user;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA btracker_endpoints TO hafbe_user;

GRANT USAGE ON SCHEMA hafah_python TO hafbe_user;
GRANT SELECT ON ALL TABLES IN SCHEMA hafah_python TO hafbe_user;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA hafah_python TO hafbe_user;

GRANT USAGE ON SCHEMA hafbe_app TO hafbe_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hafbe_app TO hafbe_user;
GRANT SELECT ON ALL TABLES IN SCHEMA hafbe_app TO hafbe_user;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA hafbe_app TO hafbe_user;

GRANT hafbe_user TO hafbe_owner;
