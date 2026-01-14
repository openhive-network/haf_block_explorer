#!/bin/bash

set -euo pipefail

POSTGRES_HOST=${POSTGRES_HOST:-"localhost"}
POSTGRES_PORT=${POSTGRES_PORT:-5432}
owner_role=hafbe_owner
BTRACKER_SCHEMA=hafbe_bal
REPTRACKER_SCHEMA=reptracker_app
SWAGGER_URL="{hafbe-host}"


print_help () {
cat <<EOF
  Usage: $0 [OPTION[=VALUE]]...

  Sets up a database, already filled by HAF instance, to work with haf_be application.
  OPTIONS:
    --host=VALUE                      PostgreSQL host location (defaults to localhost)
    --port=NUMBER                     PostgreSQL operating port (defaults to 5432)
    --only-apps                       Set up only HAfAH and Balance Tracker and Reputation Tracker, without HAF Block Explorer
    --only-hafbe                      Don't set up HAfAH and Balance Tracker and Reputation Tracker, just HAF Block Explorer
    --swagger-url=URL                 Allows to specify a server URL
    --is_forking=TRUE/FALSE           Allows to specify if app should be forking or not (defaults to true)

EOF
}

ONLY_APPS=0
ONLY_HAFBE=0
POSTGRES_APP_NAME=block_explorer_install

IS_FORKING=${IS_FORKING:-"true"}

while [ $# -gt 0 ]; do
  case "$1" in
    --host=*)
        POSTGRES_HOST="${1#*=}"
        ;;
    --port=*)
        POSTGRES_PORT="${1#*=}"
        ;;
    --btracker-schema=*)
        BTRACKER_SCHEMA="${1#*=}"
        ;;
    --reptracker-schema=*)
        REPTRACKER_SCHEMA="${1#*=}"
        ;;
    --swagger-url=*)
        SWAGGER_URL="${1#*=}"
        ;;
    --is_forking=*)
        IS_FORKING="${1#*=}"
        ;;
    --help|-h|-\?)
        print_help
        exit 0
        ;;
    --only-apps)
        ONLY_APPS=1
        ;;
    --only-hafbe)
        ONLY_HAFBE=1
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

POSTGRES_ACCESS_ADMIN="postgresql://haf_admin@$POSTGRES_HOST:$POSTGRES_PORT/haf_block_log?application_name=${POSTGRES_APP_NAME}"

POSTGRES_ACCESS_OWNER="postgresql://$owner_role@$POSTGRES_HOST:$POSTGRES_PORT/haf_block_log?application_name=${POSTGRES_APP_NAME}"

find_function() {
  local schema=$1
  local function=$2
  local _result

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

# Get git directory for a submodule - handles both:
# 1. git submodule update --init: .git/modules/submodules/<name>
# 2. fetch-submodules.sh: submodules/<name>/.git
get_submodule_git_dir() {
  local submodule_name=$1
  local submodule_dir=$2
  local modules_path="$hafbe_dir/.git/modules/submodules/$submodule_name"
  if [[ -d "$modules_path" ]]; then
    echo "$modules_path"
  else
    echo "$submodule_dir/.git"
  fi
}

setup_apps() {
  pushd "$hafah_dir"
  ./scripts/setup_postgres.sh --postgres-url="$POSTGRES_ACCESS_ADMIN"
  ./scripts/generate_version_sql.bash "$hafah_dir" "$(get_submodule_git_dir hafah "$hafah_dir")"
  ./scripts/install_app.sh --postgres-url="$POSTGRES_ACCESS_ADMIN"
  popd

  pushd "$btracker_dir"
  ./scripts/generate_version_sql.sh "$btracker_dir" "$(get_submodule_git_dir btracker "$btracker_dir")"
  ./scripts/install_app.sh --postgres-url="$POSTGRES_ACCESS_ADMIN" --schema="$BTRACKER_SCHEMA"
  popd

  pushd "$reptracker_dir"
  ./scripts/generate_version_sql.sh "$reptracker_dir" "$(get_submodule_git_dir reptracker "$reptracker_dir")"
  ./scripts/install_app.sh --postgres-url="$POSTGRES_ACCESS_ADMIN" --schema="$REPTRACKER_SCHEMA"
  popd

  pushd "$hafbe_dir"
  ./scripts/generate_version_sql.sh "$hafbe_dir"
  popd
}

setup_api() {
  # setup db schema
  psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -f "$db_dir/builtin_roles.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -c "SET custom.is_forking = '$IS_FORKING'; SET SEARCH_PATH TO ${BTRACKER_SCHEMA};" -f "$db_dir/hafbe_app.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$db_dir/process_account_stats.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$db_dir/process_block_operations.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$db_dir/process_transaction_stats.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$db_dir/process_witness_stats.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$db_dir/process_witness_votes.sql"

  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -c "SELECT hive.app_state_provider_import('METADATA', 'hafbe_app');"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -c "SELECT hive.app_state_provider_import('KEYAUTH', 'hafbe_app');"
  psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "GRANT ALL ON TABLE hafbe_app.app_status TO $owner_role;"

  # setup backend schema (inline creation)
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -c "CREATE SCHEMA IF NOT EXISTS hafbe_backend AUTHORIZATION hafbe_owner;"

  # openapi types (consolidated domain files)
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend_types/enums.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend_types/blocks.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend_types/accounts.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend_types/witnesses.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend_types/operations.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend_types/transactions.sql"

  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/utilities/blocksearch.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/endpoint_helpers/blocksearch_filters.sql"

  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/endpoint_helpers/account.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/endpoint_helpers/proxies.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/endpoint_helpers/transactions.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/endpoint_helpers/authority.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/endpoint_helpers/comment_operations.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/endpoint_helpers/comment_permlinks.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/endpoint_helpers/witness.sql"

  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -c "SET SEARCH_PATH TO ${BTRACKER_SCHEMA};" -f "$backend/utilities/views.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/utilities/exceptions.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/utilities/sync_time.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/utilities/validators.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/utilities/operation_types.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/utilities/blocks.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/utilities/witness.sql"

  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/operation_parsers/account_operations.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/operation_parsers/witness_operations.sql"

  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/endpoint_helpers/blocks.sql"

  # openapi endpoints
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -c "SET custom.swagger_url = '$SWAGGER_URL';" -f "$endpoints/endpoint_schema.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/accounts/get_account_authority.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/accounts/get_account.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/accounts/get_account_proxies_power.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/accounts/get_comment_operations.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/accounts/get_comment_permlinks.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/block-search/get_block_by_op.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/transactions/get_transaction_statistics.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/other/get_hafbe_version.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/other/get_input_type.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/other/get_latest_blocks.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/other/get_hafbe_last_synced_block.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/witnesses/get_witness_voters_num.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/witnesses/get_witness_voters.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/witnesses/get_witness_votes_history.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/witnesses/get_witness.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/witnesses/get_witnesses.sql"

  # must be done by admin
  psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -f "$hafbe_dir/scripts/set_version_in_sql.pgsql"

  # Role grants (inline, following btracker pattern)
  psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "SET ROLE hafbe_owner;GRANT USAGE ON SCHEMA hafbe_app TO hafbe_user;"
  psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "SET ROLE hafbe_owner;GRANT USAGE ON SCHEMA hafbe_endpoints TO hafbe_user;"
  psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "SET ROLE hafbe_owner;GRANT USAGE ON SCHEMA hafbe_backend TO hafbe_user;"
  psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "SET ROLE hafbe_owner;GRANT SELECT ON ALL TABLES IN SCHEMA hafbe_backend TO hafbe_user;"
  psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "SET ROLE hafbe_owner;GRANT SELECT ON ALL TABLES IN SCHEMA hafbe_endpoints TO hafbe_user;"
  psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "SET ROLE hafbe_owner;GRANT SELECT ON ALL TABLES IN SCHEMA hafbe_app TO hafbe_user;"

  # Allow hived to fullfil vacuum full requests
  psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "SET ROLE hafbe_owner;GRANT MAINTAIN ON ALL TABLES IN SCHEMA hafbe_app TO hived_group;"
  psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "SET ROLE hafbe_owner;GRANT ALL ON SCHEMA hafbe_app TO hived_group;"

  # Register HAF index dependencies
  echo 'Registering HAF index dependencies...'
  psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -f "$db_dir/indexes.sql"
}

SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"

endpoints="$SCRIPT_DIR/../endpoints"
backend="$SCRIPT_DIR/../backend"
backend_types="$SCRIPT_DIR/../backend/types"
db_dir="$SCRIPT_DIR/../db"
hafah_dir="$SCRIPT_DIR/../submodules/hafah"
btracker_dir="$SCRIPT_DIR/../submodules/btracker"
reptracker_dir="$SCRIPT_DIR/../submodules/reptracker"
hafbe_dir="$SCRIPT_DIR/.."

if [ "$ONLY_HAFBE" -eq 0 ]; then
  setup_apps
fi

if [ "$ONLY_APPS" -eq 0 ]; then
  setup_api
fi

