#!/bin/bash

set -euo pipefail

# Script location
SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
HAFBE_DIR="$SCRIPT_DIR/.."

# Capture original args for the install-lock re-exec below.
ORIGINAL_ARGS=("$@")

POSTGRES_HOST=${POSTGRES_HOST:-"localhost"}
POSTGRES_PORT=${POSTGRES_PORT:-5432}
POSTGRES_USER=${POSTGRES_USER:-"haf_admin"}
BTRACKER_SCHEMA=${BTRACKER_SCHEMA:-"hafbe_bal"}
REPTRACKER_SCHEMA=${REPTRACKER_SCHEMA:-"reptracker_app"}
SWAGGER_URL=${SWAGGER_URL:-"{hafbe-host}"}
LOG_FILE=${LOG_FILE:-"install_app.log"}
BLOCKSEARCH_INDEXES=${BLOCKSEARCH_INDEXES:-"false"}


print_help () {
cat <<EOF
  Usage: $0 [OPTION[=VALUE]]...

  Sets up a database, already filled by HAF instance, to work with haf_be application.
  OPTIONS:
    --host=VALUE                      PostgreSQL host location (defaults to localhost)
    --port=NUMBER                     PostgreSQL operating port (defaults to 5432)
    --user=NAME                       PostgreSQL user (defaults to haf_admin)
    --btracker-schema=NAME            Balance Tracker schema name (defaults to hafbe_bal)
    --reptracker-schema=NAME          Reputation Tracker schema name (defaults to reptracker_app)
    --swagger-url=URL                 Allows to specify a server URL
    --is_forking=TRUE/FALSE           Allows to specify if app should be forking or not (defaults to true)
    --log-file=PATH                   Log file location (defaults to install_app.log, set to 'STDOUT' for no log file)
    --blocksearch-indexes=TRUE/FALSE  Create block search indexes (defaults to false)
    --only-apps                       Set up only Balance Tracker and Reputation Tracker, without HAF Block Explorer
    --only-hafbe                      Don't set up HAfAH and Balance Tracker and Reputation Tracker, just HAF Block Explorer

EOF
}

ONLY_APPS=0
ONLY_HAFBE=0
IS_FORKING=${IS_FORKING:-"true"}

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
    --log-file=*)
        LOG_FILE="${1#*=}"
        ;;
    --blocksearch-indexes=*)
        BLOCKSEARCH_INDEXES="${1#*=}"
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

POSTGRES_ACCESS="postgresql://$POSTGRES_USER@$POSTGRES_HOST:$POSTGRES_PORT/haf_block_log?application_name=block_explorer_install"

# Re-exec under the install-lock wrapper if not already running under it AND
# the wrapper plus python3 are actually available (e.g. inside the production
# install image). Holds an exclusive advisory lock on 'haf_block_explorer' for
# the lifetime of this script. The btracker (--schema=hafbe_bal) and
# reptracker sub-installers invoked from setup_apps() inherit
# HAF_INSTALL_LOCK_HELD=1 and skip their own re-exec, so they all run under
# this single lock. When the wrapper isn't installed (e.g. running this
# script directly on a CI runner host outside the production image), skip the
# re-exec and run without the lock -- the lock is a production safety
# mechanism, not a correctness requirement for tests.
if [[ -z "${HAF_INSTALL_LOCK_HELD:-}" ]]; then
  if command -v python3 >/dev/null 2>&1 && [[ -f /usr/local/bin/install_with_app_lock.py ]]; then
    export HAF_INSTALL_LOCK_HELD=1
    exec python3 /usr/local/bin/install_with_app_lock.py haf_block_explorer "$POSTGRES_ACCESS" "$0" "${ORIGINAL_ARGS[@]}"
  else
    echo "WARNING: install_with_app_lock.py wrapper not found; running install without HAF advisory lock (expected in CI test setups, not in production install images)." >&2
    export HAF_INSTALL_LOCK_HELD=1
  fi
fi

# Get git directory for a submodule - handles both:
# 1. git submodule update --init: .git/modules/submodules/<name>
# 2. fetch-submodules.sh: submodules/<name>/.git
get_submodule_git_dir() {
  local submodule_name=$1
  local submodule_dir=$2
  local modules_path="$HAFBE_DIR/.git/modules/submodules/$submodule_name"
  if [[ -d "$modules_path" ]]; then
    echo "$modules_path"
  else
    echo "$submodule_dir/.git"
  fi
}

setup_apps() {
  # Stage 1: Generate version SQL for all modules
  echo "Generating version SQL for all modules..."
  "$HAFBE_DIR/submodules/btracker/scripts/generate_version_sql.sh"   "$HAFBE_DIR/submodules/btracker" "$(get_submodule_git_dir btracker "$HAFBE_DIR/submodules/btracker")"
  "$HAFBE_DIR/submodules/reptracker/scripts/generate_version_sql.sh" "$HAFBE_DIR/submodules/reptracker" "$(get_submodule_git_dir reptracker "$HAFBE_DIR/submodules/reptracker")"
  "$HAFBE_DIR/scripts/generate_version_sql.sh" "$HAFBE_DIR"

  # Stage 2: Install apps (HAfAH is installed separately via its own Docker service)
  echo "Installing Balance Tracker..."
  "$HAFBE_DIR/submodules/btracker/scripts/install_app.sh"   --postgres-url="$POSTGRES_ACCESS" --schema="$BTRACKER_SCHEMA"

  echo "Installing Reputation Tracker..."
  "$HAFBE_DIR/submodules/reptracker/scripts/install_app.sh" --postgres-url="$POSTGRES_ACCESS" --schema="$REPTRACKER_SCHEMA"
}

setup_api() {
  echo "Setting up database roles..."
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/db/builtin_roles.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -c "SET SEARCH_PATH TO ${BTRACKER_SCHEMA}; SET custom.is_forking = '$IS_FORKING';" -f "$HAFBE_DIR/db/hafbe_app.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -c "SET custom.swagger_url = '$SWAGGER_URL';" -f "$HAFBE_DIR/endpoints/endpoint_schema.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -c "SET SEARCH_PATH TO ${BTRACKER_SCHEMA};"   -f "$HAFBE_DIR/backend/utilities/views.sql"

  echo "Installing operation parsers (required by processing functions)..."
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/backend/operation_parsers/account_operations.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/backend/operation_parsers/witness_operations.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/backend/operation_parsers/witness_stats_parsers.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/backend/operation_parsers/proposal_operations.sql"

  echo "Installing block processing functions..."
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/db/process_account_stats.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/db/process_block_operations.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/db/process_transaction_stats.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/db/process_witness_stats.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/db/process_witness_votes.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/db/process_proposals.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/db/process_proposal_vote_stats_cache.sql"

  echo "Installing OpenAPI types..."
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/endpoints/types/enums.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/endpoints/types/blocks.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/endpoints/types/accounts.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/endpoints/types/witnesses.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/endpoints/types/operations.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/endpoints/types/transactions.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/endpoints/types/proposals.sql"

  echo "Installing backend utilities..."
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/backend/utilities/constants.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/backend/utilities/exceptions.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/backend/utilities/sync_time.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/backend/utilities/validators.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/backend/utilities/operation_types.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/backend/utilities/blocks.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/backend/utilities/witness.sql"
  # Types before the functions that return them: these DROP ... CASCADE, which would
  # otherwise take the blocksearch_filters.sql gatherers down with them.
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/backend/types/blocksearch.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/backend/utilities/blocksearch.sql"

  echo "Installing backend helpers..."
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/backend/endpoint_helpers/blocksearch_filters.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/backend/endpoint_helpers/blocks.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/backend/endpoint_helpers/account.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/backend/endpoint_helpers/proxies.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/backend/endpoint_helpers/transactions.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/backend/endpoint_helpers/operation_type_stats.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/backend/endpoint_helpers/total_wallet_addresses.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/backend/endpoint_helpers/authority.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/backend/endpoint_helpers/comment_operations.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/backend/endpoint_helpers/comment_permlinks.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/backend/endpoint_helpers/witness.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/backend/endpoint_helpers/proposal.sql"
  # sync_status() needs the sub-app context names (context name = schema name);
  # pass them via custom.* GUCs so the DO block can bake them into the function.
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -c "SET custom.btracker_schema = '${BTRACKER_SCHEMA}'; SET custom.reptracker_schema = '${REPTRACKER_SCHEMA}';" -f "$HAFBE_DIR/backend/endpoint_helpers/sync_status.sql"

  echo "Installing REST API endpoints..."
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/endpoints/accounts/get_account_authority.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/endpoints/accounts/get_account.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/endpoints/accounts/get_account_proxies_power.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/endpoints/accounts/get_comment_operations.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/endpoints/accounts/get_comment_permlinks.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/endpoints/accounts/get_total_wallet_addresses.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/endpoints/block-search/get_block_by_op.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/endpoints/transactions/get_transaction_statistics.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/endpoints/transactions/get_operation_type_statistics.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/endpoints/other/get_hafbe_version.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/endpoints/other/get_input_type.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/endpoints/other/get_latest_blocks.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/endpoints/other/get_hafbe_last_synced_block.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/endpoints/other/get_hafbe_sync_status.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/endpoints/witnesses/get_witness_voters_num.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/endpoints/witnesses/get_witness_voters.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/endpoints/witnesses/get_witness_votes_history.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/endpoints/witnesses/get_witness.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/endpoints/witnesses/get_witnesses.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/endpoints/proposals/get_proposal_votes_history.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/endpoints/proposals/get_proposals.sql"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/endpoints/proposals/get_proposal_votes.sql"

  echo "Setting application version..."
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -f "$HAFBE_DIR/scripts/set_version_in_sql.pgsql"

  echo "Configuring permissions..."
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -c "SET ROLE hafbe_owner;GRANT USAGE ON SCHEMA hafbe_app TO hafbe_user;"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -c "SET ROLE hafbe_owner;GRANT USAGE ON SCHEMA hafbe_endpoints TO hafbe_user;"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -c "SET ROLE hafbe_owner;GRANT USAGE ON SCHEMA hafbe_backend TO hafbe_user;"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -c "SET ROLE hafbe_owner;GRANT SELECT ON ALL TABLES IN SCHEMA hafbe_backend TO hafbe_user;"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -c "SET ROLE hafbe_owner;GRANT SELECT ON ALL TABLES IN SCHEMA hafbe_endpoints TO hafbe_user;"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -c "SET ROLE hafbe_owner;GRANT SELECT ON ALL TABLES IN SCHEMA hafbe_app TO hafbe_user;"

  # Allow hived to fullfil vacuum full requests
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -c "SET ROLE hafbe_owner;GRANT MAINTAIN ON ALL TABLES IN SCHEMA hafbe_app TO hived_group;"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -c "SET ROLE hafbe_owner;GRANT ALL ON SCHEMA hafbe_app TO hived_group;"

  echo "Storing blocksearch indexes configuration..."
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -c "ALTER TABLE hafbe_app.app_status ADD COLUMN IF NOT EXISTS blocksearch_indexes BOOLEAN NOT NULL DEFAULT FALSE;"
  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -c "UPDATE hafbe_app.app_status SET blocksearch_indexes = '${BLOCKSEARCH_INDEXES}';"

  echo "Installation complete."
}

main() {
  if [ "$ONLY_HAFBE" -eq 0 ]; then
    setup_apps
  fi

  if [ "$ONLY_APPS" -eq 0 ]; then
    setup_api
  fi
}

# Run with logging
if [[ "$LOG_FILE" == "STDOUT" ]]; then
  main
else
  echo "Logging to: $LOG_FILE"
  main 2>&1 | tee "$LOG_FILE"
fi

