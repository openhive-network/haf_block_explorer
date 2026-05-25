#!/bin/bash

set -e

function print_help () {
cat <<-EOF
Usage: $0 [OPTION[=VALUE]]...

Script that waits for HAF Block Explorer to finish processing blocks and
for all registered indexes to be created. To be used in CI.
OPTIONS:
    --postgres-access=URL     PostgreSQL URL
    --target-block=N          Wait for hafbe_app to reach block N (uses direct
                              context check instead of hive.is_app_in_sync;
                              useful for mock/test pipelines where the context
                              was rewound via SQL and LIVE-mode transition is
                              not guaranteed)
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

TARGET_BLOCK=""

while [ $# -gt 0 ]; do
  case "$1" in
    --postgres-access=*|--postgress-access=*)
        POSTGRES_ACCESS="${1#*=}"
        ;;
    --target-block=*)
        TARGET_BLOCK="${1#*=}"
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
if [[ -n "$TARGET_BLOCK" ]]; then
    # Mock/test mode: wait for hafbe_app to reach a specific block number.
    # hive.is_app_in_sync() requires a proper LIVE-mode HAF transition which
    # does not happen when contexts are rewound via direct SQL UPDATE (as in
    # the mock data pipeline).  Checking current_block_num directly is
    # equivalent for our purposes.
    wait_for_condition \
        "SELECT (current_block_num >= ${TARGET_BLOCK})::INT FROM hafd.contexts WHERE name='hafbe_app';" \
        "Waiting for hafbe_app to reach block ${TARGET_BLOCK}..." \
        60
else
    wait_for_condition \
        "SELECT hive.is_app_in_sync('hafbe_app')::INT;" \
        "Waiting for HAF Block Explorer to finish processing blocks..." \
        60
fi
echo "Block processing is finished."

# Step 2: Create HAFBE indexes if not already created
# create_hafbe_indexes() handles hafbe_app table indexes AND registers HAF table
# indexes. In CI there's no hived poll_and_create_indexes() thread, so we must
# also explicitly restore the registered HAF indexes.
echo "Step 2: Creating HAFBE application indexes..."
psql "$POSTGRES_ACCESS" --command="SELECT hafbe_app.create_hafbe_indexes();"
echo "HAFBE application indexes created."

echo "Step 3: Creating registered HAF table indexes..."
psql "$POSTGRES_ACCESS" --command="SELECT hive.app_restore_indexes('hafbe_app');"
echo "HAF table indexes created."

# Step 4: Verify all registered indexes are created
echo "Step 4: Verifying all registered indexes..."
wait_for_condition \
    "SELECT hive.check_if_registered_indexes_created('hafbe_app')::INT;" \
    "Waiting for registered indexes to be created..." \
    60
echo "All registered indexes are created."

# Step 5: Flush WAL to disk after heavy operations
# finalize_massive_sync() converts UNLOGGED tables to LOGGED (full table WAL write)
# + index restoration generates massive WAL. Without this checkpoint, the shutdown
# template's CHECKPOINT can fail (overloaded checkpointer), causing non-clean shutdown
# and corrupted pgdata in cache.
echo "Step 5: Running CHECKPOINT to flush WAL from index creation..."
psql "$POSTGRES_ACCESS" --command="CHECKPOINT;"
echo "CHECKPOINT complete."

echo "HAF Block Explorer startup complete."
