#!/bin/bash

set -e
set -o pipefail

SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"

print_help () {
cat <<EOF
  Usage: $0 [OPTION[=VALUE]]...

  Drops database.
  OPTIONS:
    --host=VALUE             PostgreSQL host location (defaults to localhost)
    --port=NUMBER            PostgreSQL operating port (defaults to 5432)
    --skip-btracker          Allows to skip cleanup of Balance Tracker application
    --user=VALUE             PostgreSQL user (defaults to haf_admin)
EOF
}

POSTGRES_HOST="localhost"
POSTGRES_PORT=5432
POSTGRES_USER="haf_admin"
CLEAN_BTRACKER=1

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
    --skip-btracker)
        CLEAN_BTRACKER=0
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
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=OFF" -c "DROP SCHEMA IF EXISTS hafbe_views CASCADE;"
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=OFF" -c "do \$\$ BEGIN if hive.app_context_exists('hafbe_app') THEN PERFORM hive.app_state_provider_drop_all('hafbe_app'); PERFORM hive.app_remove_context('hafbe_app'); end if; END \$\$"
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=OFF" -c "DROP SCHEMA IF EXISTS hafbe_app CASCADE;"

    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=OFF" -c "DROP SCHEMA IF EXISTS hafbe_views CASCADE;"
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=OFF" -c "DROP SCHEMA IF EXISTS hafbe_types CASCADE;"
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=OFF" -c "DROP SCHEMA IF EXISTS hafbe_exceptions CASCADE;"
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=OFF" -c "DROP SCHEMA IF EXISTS hafbe_backend CASCADE;"
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=OFF" -c "DROP SCHEMA IF EXISTS hafbe_indexes CASCADE;"
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=OFF" -c "DROP SCHEMA IF EXISTS hafbe_endpoints CASCADE;"

    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=OFF" -c "DROP FUNCTION IF EXISTS hive.hive_hafbe_app_metadata_revert_delete(bigint);"
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=OFF" -c "DROP FUNCTION IF EXISTS hive.hive_hafbe_app_metadata_revert_insert(bigint);"
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=OFF" -c "DROP FUNCTION IF EXISTS hive.hive_hafbe_app_metadata_revert_update(bigint, bigint);"

    psql "$POSTGRES_ACCESS_ADMIN"  -c "REASSIGN OWNED BY hafbe_owner TO postgres; " || true;
    psql "$POSTGRES_ACCESS_ADMIN"  -c "DROP OWNED BY hafbe_owner" || true
    psql "$POSTGRES_ACCESS_ADMIN"  -c "DROP ROLE IF EXISTS hafbe_owner" || true

    psql "$POSTGRES_ACCESS_ADMIN" -c "REASSIGN OWNED BY hafbe_user TO postgres; " || true
    psql "$POSTGRES_ACCESS_ADMIN" -c "DROP OWNED BY hafbe_user" || true
    psql "$POSTGRES_ACCESS_ADMIN" -c "DROP ROLE IF EXISTS hafbe_user" || true

    if [ "${CLEAN_BTRACKER}" -eq 1 ]; then
      "${SCRIPT_DIR}/../submodules/btracker/scripts/uninstall_app.sh" --host="${POSTGRES_HOST}" --port="${POSTGRES_PORT}" --user="${POSTGRES_USER}"
    fi
}

uninstall_app
