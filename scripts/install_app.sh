#!/bin/bash

set -euo pipefail

POSTGRES_HOST=${POSTGRES_HOST:-"localhost"}
POSTGRES_PORT=${POSTGRES_PORT:-5432}
owner_role=hafbe_owner
BLOCKSEARCH_INDEXES=false
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
    --indexes-only                    Only creates indexes (ignored when --only-apps is specified)
    --schema-only                     Only creates schema, but not indexes (ignored when --only-apps is specified)
    --blocksearch-indexes=true/false  If true, blocksearch indexes will be created on setup (defaults to false)
    --swagger-url=URL        Allows to specify a server URL

EOF
}

ONLY_APPS=0
ONLY_HAFBE=0
POSTGRES_APP_NAME=block_explorer_install

while [ $# -gt 0 ]; do
  case "$1" in
    --host=*)
        POSTGRES_HOST="${1#*=}"
        ;;
    --port=*)
        POSTGRES_PORT="${1#*=}"
        ;;
    --blocksearch-indexes=*)
        BLOCKSEARCH_INDEXES="${1#*=}"
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

setup_apps() {
  pushd "$hafah_dir"
  ./scripts/setup_postgres.sh --postgres-url="$POSTGRES_ACCESS_ADMIN"
  ./scripts/generate_version_sql.bash "$hafah_dir" "$hafbe_dir/.git/modules/submodules/hafah"
  ./scripts/install_app.sh --postgres-url="$POSTGRES_ACCESS_ADMIN"
  popd

  pushd "$btracker_dir"
  ./scripts/generate_version_sql.sh "$btracker_dir" "$hafbe_dir/.git/modules/submodules/btracker"
  ./scripts/install_app.sh --postgres-url="$POSTGRES_ACCESS_ADMIN" --schema="$BTRACKER_SCHEMA"
  popd

  pushd "$reptracker_dir"
  ./scripts/generate_version_sql.sh "$reptracker_dir" "$hafbe_dir/.git/modules/submodules/reptracker"
  ./scripts/install_app.sh --postgres-url="$POSTGRES_ACCESS_ADMIN" --schema="$REPTRACKER_SCHEMA"
  popd

  pushd "$hafbe_dir"
  ./scripts/generate_version_sql.sh "$hafbe_dir"
  popd
}

setup_api() {
  # setup db schema

  psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -f "$db_dir/builtin_roles.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$db_dir/database_schema.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -c "SET SEARCH_PATH TO ${BTRACKER_SCHEMA};" -f "$db_dir/hafbe_app_helpers.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$db_dir/hafbe_app_indexes.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$db_dir/main_loop.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$db_dir/process_blocks.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$db_dir/process_block_range.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$db_dir/process_operations.sql"


  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -c "SELECT hive.app_state_provider_import('METADATA', 'hafbe_app');"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -c "SELECT hive.app_state_provider_import('KEYAUTH', 'hafbe_app');"
  psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "GRANT ALL ON TABLE hafbe_app.app_status TO $owner_role;"

  # setup backend schema
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/backend_schema.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/hafbe_exceptions.sql"

  # openapi types
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend_types/backend_types.sql"

  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend_types/accounts/account_authority.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend_types/accounts/account.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend_types/accounts/permlink_history.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend_types/blocks/blocksearch.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend_types/blocks/latest_blocks.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend_types/other/input_type.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend_types/operations/operation.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend_types/witnesses/witness_voters.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend_types/witnesses/witness_votes_history_record.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend_types/witnesses/witness.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend_types/transactions/granularity.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend_types/transactions/transaction_stats.sql"

  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -c "SET SEARCH_PATH TO ${BTRACKER_SCHEMA};" -f "$backend/hafbe_views.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/get_account_data.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/witness.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/get_sync_time.sql"


  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/blocksearch/blocksearch_backend.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/blocksearch/filtering_functions/default.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/blocksearch/filtering_functions/by_operation.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/blocksearch/filtering_functions/by_operation_key_value.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/blocksearch/filtering_functions/by_multiple_operations.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/blocksearch/filtering_functions/by_account.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/blocksearch/filtering_functions/by_account_operation.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/blocksearch/filtering_functions/by_account_operation_key_value.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/blocksearch/filtering_functions/by_account_multi_operations.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/aggregated_transactions.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/authority.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/account.sql"

  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/blocksearch/get_blocks_by_ops.sql"

  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/comment_operations.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/comment_permlinks.sql"

  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$account_dump/account_stats_hafbe.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$account_dump/compare_accounts.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$account_dump/compare_witnesses.sql"

  # openapi endpoints
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -c "SET custom.swagger_url = '$SWAGGER_URL';" -f "$endpoints/endpoint_schema.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/accounts/get_account_authority.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/accounts/get_account.sql"
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
  psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -f "$backend/hafbe_roles.sql"
  psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -f "$hafbe_dir/scripts/set_version_in_sql.pgsql"

}

# blockseach indexes are registered when flag is set to true
register_blocksearch_indexes() {
  echo 'Registering block search indexes...'
  psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -f "$backend/hafbe_blocksearch_indexes.sql"
}

register_commentsearch_indexes() {
  echo 'Registering comment search indexes...'
  psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -f "$backend/hafbe_commentsearch_indexes.sql"
}

register_haf_indexes() {
  echo 'Registering haf indexes...'
  psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -f "$db_dir/create_haf_indexes.sql"
}

SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"

account_dump="$SCRIPT_DIR/../account_dump"
endpoints="$SCRIPT_DIR/../endpoints"
backend="$SCRIPT_DIR/../backend"
backend_types="$SCRIPT_DIR/../backend/types"
db_dir="$SCRIPT_DIR/../database"
hafah_dir="$SCRIPT_DIR/../submodules/hafah"
btracker_dir="$SCRIPT_DIR/../submodules/btracker"
reptracker_dir="$SCRIPT_DIR/../submodules/reptracker"
hafbe_dir="$SCRIPT_DIR/.."

if [ "$ONLY_HAFBE" -eq 0 ]; then
  setup_apps
fi

if [ "$ONLY_APPS" -eq 0 ]; then
  setup_api
  if [ "$BLOCKSEARCH_INDEXES" = "true" ]; then
    register_blocksearch_indexes
  fi
  register_haf_indexes
  register_commentsearch_indexes
fi

