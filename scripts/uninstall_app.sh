#!/bin/bash

set -e
set -o pipefail

print_help () {
cat <<EOF
  Usage: $0 [OPTION[=VALUE]]...

  Drops database.
  OPTIONS:
    --host=VALUE             PostgreSQL host location (defaults to localhost)
    --port=NUMBER            PostgreSQL operating port (defaults to 5432)
    --only-hafbe             Don't do cleanup for hafah, btracker, just the block explorer
    --user=VALUE             PostgreSQL user (defaults to haf_admin)
EOF
}

POSTGRES_HOST="localhost"
POSTGRES_PORT=5432
POSTGRES_USER="haf_admin"
ONLY_HAFBE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --host=*)
        POSTGRES_HOST="${1#*=}"
        ;;
    --port=*)
        POSTGRES_PORT="${1#*=}"
        ;;
    --user=*)
        POSTGRES_USER="${1#*=}"
        ;;
    --only-hafbe)
        ONLY_HAFBE=1
        ;;
    --help|-h|-?)
        print_help
        exit 0
        ;;
    -*)
        echo "ERROR: '$1' is not a valid option"
        echo
        print_help
        exit 1
        ;;
    *)
        echo "ERROR: '$1' is not a valid argument"
        echo
        print_help
        exit 2
        ;;
    esac
    shift
done

POSTGRES_ACCESS_ADMIN="postgresql://$POSTGRES_USER@$POSTGRES_HOST:$POSTGRES_PORT/haf_block_log"

uninstall_app() {
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "DROP SCHEMA IF EXISTS hafbe_views CASCADE;"
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "do \$\$ BEGIN if hive.app_context_exists('hafbe_app') THEN perform hive.app_remove_context('hafbe_app'); end if; END \$\$"
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "do \$\$ BEGIN if hive.app_context_exists('btracker_app') THEN perform hive.app_remove_context('btracker_app'); end if; END \$\$"
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "DROP SCHEMA IF EXISTS hafbe_app CASCADE;"

    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "DROP SCHEMA IF EXISTS btracker_app CASCADE;"
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "DROP SCHEMA IF EXISTS btracker_account_dump CASCADE;"
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "DROP SCHEMA IF EXISTS btracker_endpoints CASCADE;"


    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "DROP SCHEMA IF EXISTS hafbe_views CASCADE;"
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "DROP SCHEMA IF EXISTS hafbe_types CASCADE;"
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "DROP SCHEMA IF EXISTS hafbe_exceptions CASCADE;"
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "DROP SCHEMA IF EXISTS hafbe_backend CASCADE;"
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "DROP SCHEMA IF EXISTS hafbe_indexes CASCADE;"
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "DROP SCHEMA IF EXISTS hafbe_endpoints CASCADE;"

    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "DROP SCHEMA IF EXISTS hafah_backend CASCADE;"
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "DROP SCHEMA IF EXISTS hafah_endpoints CASCADE;"
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "DROP SCHEMA IF EXISTS hafah_python CASCADE;"

    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "DROP FUNCTION IF EXISTS hive.hive_hafbe_app_metadata_revert_delete(bigint);"
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "DROP FUNCTION IF EXISTS hive.hive_hafbe_app_metadata_revert_insert(bigint);"
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "DROP FUNCTION IF EXISTS hive.hive_hafbe_app_metadata_revert_update(bigint, bigint);"

    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "REASSIGN OWNED BY btracker_owner TO postgres; "
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "DROP OWNED BY btracker_owner"
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "DROP ROLE btracker_owner"

    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "REASSIGN OWNED BY btracker_user TO postgres; "
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "DROP OWNED BY btracker_user"
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "DROP ROLE btracker_user"


    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "REASSIGN OWNED BY hafbe_owner TO postgres; "
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "DROP OWNED BY hafbe_owner"
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "DROP ROLE hafbe_owner"

    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "REASSIGN OWNED BY hafbe_user TO postgres; "
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "DROP OWNED BY hafbe_user"
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "DROP ROLE hafbe_user"

    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "REASSIGN OWNED BY hafah_owner TO postgres; "
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "DROP OWNED BY hafah_owner"
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "DROP ROLE hafah_owner"

    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "REASSIGN OWNED BY hafah_user TO postgres; "
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "DROP OWNED BY hafah_user"
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "DROP ROLE hafah_user"


}

uninstall_app