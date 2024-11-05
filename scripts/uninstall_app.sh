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
    --user=VALUE             PostgreSQL user (defaults to haf_admin)
EOF
}

POSTGRES_HOST="localhost"
POSTGRES_PORT=5432
POSTGRES_USER="haf_admin"
DROP_INDEXES=0

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
    --drop-indexes*)
        DROP_INDEXES=1
        ;;
    --help|-h|-\?)
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

    psql "$POSTGRES_ACCESS_ADMIN"  -c "DROP OWNED BY hafbe_owner CASCADE" || true
    psql "$POSTGRES_ACCESS_ADMIN"  -c "DROP ROLE IF EXISTS hafbe_owner" || true

    psql "$POSTGRES_ACCESS_ADMIN" -c "DROP OWNED BY hafbe_user CASCADE" || true
    psql "$POSTGRES_ACCESS_ADMIN" -c "DROP ROLE IF EXISTS hafbe_user" || true

    if [ "${DROP_INDEXES}" -eq 1 ]; then
      echo "Attempting to drop indexes built by application"
      # WIP
      #psql -aw "$POSTGRES_ACCESS_ADMIN" -v ON_ERROR_STOP=on -c 'DROP INDEX IF EXISTS hafd.effective_comment_vote_idx;'

    else
      echo "Indexes created by application have been preserved"
    fi

}

uninstall_app
