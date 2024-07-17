#!/bin/bash

set -euo pipefail

POSTGRES_HOST=${POSTGRES_HOST:-"localhost"}
POSTGRES_PORT=${POSTGRES_PORT:-5432}
owner_role=hafbe_owner
BLOCKSEARCH_INDEXES=false
BTRACKER_SCHEMA=hafbe_bal
REPTRACKER_SCHEMA=hafbe_rep


print_help () {
cat <<EOF
  Usage: $0 [OPTION[=VALUE]]...

  Sets up a database, already filled by HAF instance, to work with haf_be application.
  OPTIONS:
    --host=VALUE             PostgreSQL host location (defaults to localhost)
    --port=NUMBER            PostgreSQL operating port (defaults to 5432)
    --only-apps              Set up only HAfAH, Balance Tracker and Reputation Tracker, without HAF Block Explorer
    --only-hafbe             Don't set up HAfAH, Balance Tracker and Reputation Tracker, just HAF Block Explorer
    --blocksearch-indexes=true/false  If true, blocksearch indexes will be created on setup (defaults to false)

EOF
}

ONLY_APPS=0
ONLY_HAFBE=0

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
    --help|-h|-?)
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

POSTGRES_ACCESS_ADMIN="postgresql://haf_admin@$POSTGRES_HOST:$POSTGRES_PORT/haf_block_log"

POSTGRES_ACCESS_OWNER="postgresql://$owner_role@$POSTGRES_HOST:$POSTGRES_PORT/haf_block_log"

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
  ./scripts/install_app.sh --postgres-url="$POSTGRES_ACCESS_ADMIN" --schema="$BTRACKER_SCHEMA"
  popd

  pushd "$reptracker_dir"
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
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -c "SET SEARCH_PATH TO ${BTRACKER_SCHEMA},${REPTRACKER_SCHEMA};" -f "$db_dir/hafbe_app_helpers.sql"
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
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend_types/accounts/comment_history.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend_types/blocks/block_raw.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend_types/blocks/block.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend_types/blocks/latest_blocks.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend_types/blocks/op_count_in_block.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend_types/blocks/block_by_ops.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend_types/transactions/transaction.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend_types/operations/operation.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend_types/operations/op_types.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend_types/witnesses/witness_voters.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend_types/witnesses/witness_votes_history_record.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend_types/witnesses/witness.sql"

  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -c "SET SEARCH_PATH TO ${BTRACKER_SCHEMA},${REPTRACKER_SCHEMA};" -f "$backend/hafbe_views.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/get_account_data.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/get_sync_time.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/get_operation.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$backend/blocksearch_backend.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$account_dump/account_stats_hafbe.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$account_dump/compare_accounts.sql"

  # openapi endpoints
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/endpoint_schema.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/accounts/get_account_authority.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/accounts/get_account.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/accounts/get_acc_op_types.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/accounts/get_comment_operations.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/accounts/get_ops_by_account.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/blocks/get_block_op_types.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/blocks/get_block_raw.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/blocks/get_block.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/blocks/get_latest_blocks.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/blocks/get_op_count_in_block.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/blocks/get_ops_by_block_paging.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/block-numbers/get_block_by_time.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/block-numbers/get_block_by_op.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/block-numbers/get_hafbe_last_synced_block.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/block-numbers/get_head_block_num.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/other/get_hafbe_version.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/other/get_input_type.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/transactions/get_transaction.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/operations/get_operation.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/operations/get_op_types.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/operations/get_operation_keys.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/witnesses/get_witness_voters_num.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/witnesses/get_witness_voters.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/witnesses/get_witness_votes_history.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/witnesses/get_witness.sql"
  psql "$POSTGRES_ACCESS_OWNER" -v "ON_ERROR_STOP=on" -f "$endpoints/witnesses/get_witnesses.sql"

  # must be done by admin
  psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -f "$backend/hafbe_roles.sql"
  psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -f "$hafbe_dir/scripts/set_version_in_sql.pgsql"

}

create_haf_indexes() {
  if [ "$(psql "$POSTGRES_ACCESS_ADMIN" --quiet --no-align --tuples-only --command="SELECT hafbe_indexes.do_haf_indexes_exist();")" = f ]; then
    # if HAF is in massive sync, where most indexes on HAF tables have been deleted, we should wait.  We don't
    # want to add our own indexes, which would slow down massive sync, so we just wait.
    echo "Waiting for HAF to be out of massive sync"
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "SELECT hive.wait_for_ready_instance(ARRAY['hafbe_app', 'hafbe_bal', 'hafbe_rep'], interval '3 days');"

    echo "Creating indexes, this might take a while."
    # There's an un-solved bug that happens any time and app like hafbe adds/drops indexes at the same time
    # HAF is entering/leaving massive sync.  We need to prevent this, probably by having hafbe set a flag
    # that prevents haf from re-entering massive sync during the time hafbe is creating indexes
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "\timing" -f "$db_dir/create_haf_indexes.sql"
  else
    echo "HAF indexes already exist, skipping creation"
  fi
}

create_blocksearch_indexes() {
if [ "$BLOCKSEARCH_INDEXES" = "true" ] && [ "$(psql "$POSTGRES_ACCESS_ADMIN" --quiet --no-align --tuples-only --command="SELECT hafbe_indexes.do_blocksearch_indexes_exist();")" = f ]; then
  echo 'Creating blocksearch indexes...'
  psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -f "$backend/hafbe_blocksearch_indexes.sql"
  psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "UPDATE hafbe_app.app_status SET blocksearch_indexes = TRUE;"
elif [ "$(psql "$POSTGRES_ACCESS_ADMIN" --quiet --no-align --tuples-only --command="SELECT hafbe_indexes.do_blocksearch_indexes_exist();")" = t ]; then
  echo "blocksearch indexes already exist, skipping creation"
  psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "UPDATE hafbe_app.app_status SET blocksearch_indexes = TRUE;"
else 
  echo "blocksearch indexes do not exist, disabling block/comment search APIs"
  psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "UPDATE hafbe_app.app_status SET blocksearch_indexes = FALSE;"
fi
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
  create_haf_indexes
  create_blocksearch_indexes
fi

