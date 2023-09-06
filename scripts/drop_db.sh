#!/bin/bash

set -e
set -o pipefail

print_help () {
    echo "Usage: $0 [OPTION[=VALUE]]..."
    echo
    echo "Allows to setup a database already filled by HAF instance, to work with haf_be application."
    echo "OPTIONS:"
    echo "  --host=VALUE             Allows to specify a PostgreSQL host location (defaults to localhost)"
    echo "  --port=NUMBER            Allows to specify a PostgreSQL operating port (defaults to 5432)"
    echo "  --user=VALUE             Allows to specify a PostgreSQL user (defaults to haf_admin)"
}

POSTGRES_HOST="localhost"
POSTGRES_PORT=5432
POSTGRES_USER="haf_admin"

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
    --help)
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

POSTGRES_ACCESS_OWNER="postgresql://hafbe_owner@$POSTGRES_HOST:$POSTGRES_PORT/haf_block_log"

drop_db() {
    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "DROP SCHEMA IF EXISTS hafbe_views CASCADE;"
    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "SELECT hive.app_remove_context('hafbe_app');"
    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "SELECT hive.app_remove_context('btracker_app');"
    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "DROP SCHEMA IF EXISTS hafbe_app CASCADE;"

    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "DROP SCHEMA IF EXISTS btracker_app CASCADE;"
    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "DROP SCHEMA IF EXISTS btracker_account_dump CASCADE;"
    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "DROP SCHEMA IF EXISTS btracker_endpoints CASCADE;"


    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "DROP SCHEMA IF EXISTS hafbe_views CASCADE;"
    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "DROP SCHEMA IF EXISTS hafbe_types CASCADE;"
    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "DROP SCHEMA IF EXISTS hafbe_exceptions CASCADE;"
    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "DROP SCHEMA IF EXISTS hafbe_backend CASCADE;"
    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "DROP SCHEMA IF EXISTS hafbe_indexes CASCADE;"
    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "DROP SCHEMA IF EXISTS hafbe_endpoints CASCADE;"

    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "DROP SCHEMA IF EXISTS hafah_backend CASCADE;"
    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "DROP SCHEMA IF EXISTS hafah_endpoints CASCADE;"
    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "DROP SCHEMA IF EXISTS hafah_python CASCADE;"

    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "DROP FUNCTION IF EXISTS hive.hive_hafbe_app_metadata_revert_delete(bigint);"
    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "DROP FUNCTION IF EXISTS hive.hive_hafbe_app_metadata_revert_insert(bigint);"
    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "DROP FUNCTION IF EXISTS hive.hive_hafbe_app_metadata_revert_update(bigint, bigint);"

    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "REASSIGN OWNED BY btracker_owner TO postgres; "
    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "DROP OWNED BY btracker_owner"
    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "DROP ROLE btracker_owner"

    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "REASSIGN OWNED BY btracker_user TO postgres; "
    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "DROP OWNED BY btracker_user"
    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "DROP ROLE btracker_user"


    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "REASSIGN OWNED BY hafbe_owner TO postgres; "
    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "DROP OWNED BY hafbe_owner"
    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "DROP ROLE hafbe_owner"

    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "REASSIGN OWNED BY hafbe_user TO postgres; "
    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "DROP OWNED BY hafbe_user"
    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "DROP ROLE hafbe_user"

    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "REASSIGN OWNED BY hafah_owner TO postgres; "
    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "DROP OWNED BY hafah_owner"
    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "DROP ROLE hafah_owner"

    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "REASSIGN OWNED BY hafah_user TO postgres; "
    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "DROP OWNED BY hafah_user"
    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "DROP ROLE hafah_user"


}

drop_db