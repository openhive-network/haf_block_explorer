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
    local iteration=0
    while ! psql "$POSTGRES_ACCESS" --quiet --tuples-only --command="$command" | grep -q 1; do
        if [[ $SECONDS -ge $end_time ]]; then
            echo "Timeout waiting for: $message"
            echo "=== DIAGNOSTICS ==="
            psql "$POSTGRES_ACCESS" -c "SELECT name, current_block_num, irreversible_block, is_attached, last_active_at FROM hafd.contexts hc JOIN hafd.contexts_attachment hca ON hca.context_id = hc.id WHERE name IN ('hafbe_app', 'hafbe_bal');" 2>&1 || true
            psql "$POSTGRES_ACCESS" -c "SELECT * FROM hafd.contexts WHERE name IN ('hafbe_app', 'hafbe_bal');" 2>&1 || true
            psql "$POSTGRES_ACCESS" -c "SELECT pid, state, query, wait_event_type, wait_event, now()-query_start as duration FROM pg_stat_activity WHERE application_name LIKE '%block_explorer%' OR usename = 'hafbe_owner';" 2>&1 || true
            echo "=== DOCKER COMPOSE LOGS (last 200 lines) ==="
            docker compose logs --tail=200 backend-block-processing 2>&1 || docker-compose logs --tail=200 backend-block-processing 2>&1 || true
            echo "=== END DIAGNOSTICS ==="
            exit 1
        fi
        iteration=$((iteration + 1))
        if (( iteration % 15 == 0 )); then
            echo "$message ($(( SECONDS / 60 ))m elapsed)"
            psql "$POSTGRES_ACCESS" --quiet --tuples-only -c "SELECT 'hafbe_app block=' || current_block_num FROM hafd.contexts WHERE name='hafbe_app';" 2>&1 || true
        else
            echo "$message"
        fi
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
    60
echo "Block processing is finished."

# Step 2: Create registered indexes that weren't created during HAF's initial setup
# Blocksearch indexes are registered by backend-setup AFTER HAF's enable_indexes_of_irreversible()
# runs, so we need to explicitly create them here.
echo "Step 2: Creating registered indexes..."
psql "$POSTGRES_ACCESS" --command="SELECT hive.restore_indexes('hafd.operations');"
psql "$POSTGRES_ACCESS" --command="SELECT hive.restore_indexes('hafd.blocks');"
echo "Index creation initiated."

# Step 3.5: Create HAFBE application indexes if not already created
# These indexes (like witness_votes_history_witness_voter) are normally created
# during single-block processing, but CI uses cached data from MASSIVE mode
# where indexes aren't created. Create them explicitly before tests run.
echo "Step 3.5: Creating HAFBE application indexes..."
psql "$POSTGRES_ACCESS" --command="SELECT hafbe_app.create_hafbe_indexes();"
echo "HAFBE application indexes created."

# Step 3: Wait for all registered indexes to be created
echo "Step 3: Waiting for registered indexes to finish building..."
wait_for_condition \
    "SELECT hive.check_if_registered_indexes_created('hafbe_app')::INT;" \
    "Waiting for registered indexes to be created..." \
    60
echo "All registered indexes are created."

# Step 4: Flush WAL to disk after heavy operations
# finalize_massive_sync() converts UNLOGGED tables to LOGGED (full table WAL write)
# + index restoration generates massive WAL. Without this checkpoint, the shutdown
# template's CHECKPOINT can fail (overloaded checkpointer), causing non-clean shutdown
# and corrupted pgdata in cache.
echo "Step 4: Running CHECKPOINT to flush WAL from index creation..."
psql "$POSTGRES_ACCESS" --command="CHECKPOINT;"
echo "CHECKPOINT complete."

echo "HAF Block Explorer startup complete."
