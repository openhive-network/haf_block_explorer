#!/bin/bash

set -e

function print_help () {
cat <<-EOF
Usage: $0 [OPTION[=VALUE]]...

Script that waits for HAF Block Explorer to finish processing blocks and
for all registered indexes to be created. To be used in CI.
OPTIONS:
    --postgres-access=URL     PostgreSQL URL
    --help|-h|-?              Display this help screen and exit
EOF
}

function wait_for_condition() {
    local command="$1"
    local message="$2"
    local timeout_minutes="${3:-20}"

    if ! command -v psql &> /dev/null; then
        echo "Please install psql before running this script."
        exit 1
    fi

    local end_time=$((SECONDS + timeout_minutes * 60))
    while ! psql "$POSTGRES_ACCESS" --quiet --tuples-only --command="$command" | grep -q 1; do
        if [[ $SECONDS -ge $end_time ]]; then
            echo "Timeout waiting for: $message"
            exit 1
        fi
        echo "$message"
        sleep 20
    done
}

while [ $# -gt 0 ]; do
  case "$1" in
    --postgres-access=*|--postgress-access=*)
        POSTGRES_ACCESS="${1#*=}"
        ;;
    --help|-h|-\?)
        print_help
        exit 0
        ;;
    *)
        echo "ERROR: '$1' is not a valid option/positional argument"
        echo
        print_help
        exit 2
        ;;
  esac
  shift
done

POSTGRES_ACCESS=${POSTGRES_ACCESS:-postgresql://haf_admin@localhost:5432/haf_block_log}

# Step 1: Wait for block processing to complete
echo "Step 1: Waiting for block processing..."
wait_for_condition \
    "SELECT hive.is_app_in_sync('hafbe_app')::INT;" \
    "Waiting for HAF Block Explorer to finish processing blocks..." \
    20
echo "Block processing is finished."

# Step 2: Create registered indexes that weren't created during HAF's initial setup
# Blocksearch indexes are registered by backend-setup AFTER HAF's enable_indexes_of_irreversible()
# runs, so we need to explicitly create them here.
echo "Step 2: Creating registered indexes..."
psql "$POSTGRES_ACCESS" --command="SELECT hive.restore_indexes('hafd.operations');"
psql "$POSTGRES_ACCESS" --command="SELECT hive.restore_indexes('hafd.blocks');"
echo "Index creation initiated."

# Step 3: Wait for all registered indexes to be created
echo "Step 3: Waiting for registered indexes to finish building..."
wait_for_condition \
    "SELECT hive.check_if_registered_indexes_created('hafbe_app')::INT;" \
    "Waiting for registered indexes to be created..." \
    60
echo "All registered indexes are created."

echo "HAF Block Explorer startup complete."
