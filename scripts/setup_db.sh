#!/bin/bash

set -euo pipefail

SCRIPTDIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
SRCDIR="${SCRIPTDIR}/../"

POSTGRES_HOST=${POSTGRES_HOST:-"localhost"}
POSTGRES_PORT=${POSTGRES_PORT:-5432}
owner_role=hafbe_owner

print_help () {
    echo "Usage: $0 [OPTION[=VALUE]]..."
    echo
    echo "Allows to setup a database already filled by HAF instance, to work with haf_be application."
    echo "OPTIONS:"
    echo "  --host=VALUE             Allows to specify a PostgreSQL host location (defaults to localhost)"
    echo "  --port=NUMBER            Allows to specify a PostgreSQL operating port (defaults to 5432)"
    echo "  --user=VALUE             Allows to specify a PostgreSQL user (defaults to haf_admin)"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --host=*)
        POSTGRES_HOST="${1#*=}"
        ;;
    --port=*)
        POSTGRES_PORT="${1#*=}"
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

POSTGRES_ACCESS_ADMIN="postgresql://haf_admin@$POSTGRES_HOST:$POSTGRES_PORT/haf_block_log"

POSTGRES_ACCESS_OWNER="postgresql://$owner_role@$POSTGRES_HOST:$POSTGRES_PORT/haf_block_log"

find_function() {
  schema=$1
  function=$2

  _result=$(psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -f - <<-EOF
    DO \$$
    BEGIN
      IF (SELECT COUNT(1)
        FROM pg_catalog.pg_namespace n
        JOIN pg_catalog.pg_proc p ON p.pronamespace = n.oid
        WHERE n.nspname = '$schema' AND p.proname = '$function') = 0
      THEN
        RAISE NOTICE '$schema.$function() does not exist';
      END IF;
    END
    \$$;
EOF
)
}

setup_apps() {
  pushd "$hafah_dir" 
  ./scripts/setup_postgres.sh --postgres-url="$POSTGRES_ACCESS_ADMIN"
  ./scripts/generate_version_sql.bash "$PWD"
  ./scripts/setup_db.sh --postgres-url="$POSTGRES_ACCESS_ADMIN"
  popd

  pushd "$btracker_dir"
  ./scripts/setup_db.sh --postgres-url="$POSTGRES_ACCESS_ADMIN"
  popd

  pushd "$hafbe_dir"
  ./scripts/generate_version_sql.sh "$PWD"
  popd
}

setup_api() {
  # setup db schema

  psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -f "$db_dir/builtin_roles.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$db_dir/database_schema.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$db_dir/hafbe_app_helpers.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$db_dir/hafbe_app_indexes.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$db_dir/main_loop.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$db_dir/massive_processing.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$db_dir/process_block_range.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$db_dir/process_operations.sql"


  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -c "SELECT hive.app_state_provider_import('METADATA', 'hafbe_app');"
  #psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -c "SELECT hive.app_state_provider_import('KEYAUTH', 'hafbe_app');"
  psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "GRANT ALL ON TABLE hafbe_app.app_status TO $owner_role;"

  # setup backend schema
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/backend_schema.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/hafbe_exceptions.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/hafbe_backend_types.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/hafbe_endpoint_types.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/hafbe_views.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/get_account_data.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/get_sync_time.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$account_dump/account_stats_hafbe.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$account_dump/compare_accounts.sql"

  # setup endpoints schema
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/get_account.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/get_block.sql" 
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/get_input_type.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/get_operation_type.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/get_operations.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/get_transaction.sql" 
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/get_witness.sql" 

  # must be done by admin
  psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -f "$backend/hafbe_roles.sql"
  psql "$POSTGRES_ACCESS_ADMIN" -v ON_ERROR_STOP=on -f "${SRCDIR}/set_version_in_sql.pgsql"

}

create_haf_indexes() {
  echo "Creating indexes, this might take a while."
  psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "\timing" -c "SELECT hafbe_indexes.create_haf_indexes();"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f $backend/hafbe_blocksearch_indexes.sql
}

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"

account_dump="$SCRIPT_DIR/../account_dump"
endpoints="$SCRIPT_DIR/../endpoints"
backend="$SCRIPT_DIR/../backend"
db_dir="$SCRIPT_DIR/../database"
hafah_dir="$SCRIPT_DIR/../submodules/hafah"
btracker_dir="$SCRIPT_DIR/../submodules/btracker"
hafbe_dir="$SCRIPT_DIR/.."

setup_apps
setup_api
create_haf_indexes
