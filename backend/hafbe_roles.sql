-- noqa: disable=CP03

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

GRANT USAGE ON SCHEMA hafbe_app TO hafbe_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hafbe_app TO hafbe_user;
GRANT SELECT ON ALL TABLES IN SCHEMA hafbe_app TO hafbe_user;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA hafbe_app TO hafbe_user;

GRANT hafbe_user TO hafbe_owner;

-- the current version of sqlfluff doesn't understand 'GRANT MAINTAIN'
GRANT MAINTAIN ON ALL TABLES IN SCHEMA hafbe_app TO hived_group; -- noqa: PRS
GRANT ALL ON SCHEMA hafbe_app TO hived_group;

ALTER ROLE hafbe_user SET statement_timeout = '10s';
