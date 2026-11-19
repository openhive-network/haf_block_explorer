#!/bin/bash

set -e
set -o pipefail
trap 'trap - TERM INT; kill 0' TERM INT


print_help () {
cat <<EOF
  Usage: $0 [OPTION[=VALUE]]...

  Processes blocks using Haf Block Explorer
  OPTIONS:
    --host=HOST             PostgreSQL host (defaults to localhost)
    --port=PORT             PostgreSQL operating port (defaults to 5432)
    --user=USER             PostgreSQL username (defaults to hafbe_owner)
    --stop-at-block=LIMIT           Max number of blocks to process (0 for infinite, defaults to 0)
    --log-file              Log file location (defaults to hafbe_sync.log, set to 'STDOUT' to log to STDOUT only)
EOF
}

POSTGRES_HOST=${POSTGRES_HOST:-"localhost"}
POSTGRES_PORT=${POSTGRES_PORT:-5432}
POSTGRES_USER=${POSTGRES_USER:-"hafbe_owner"}
PROCESS_BLOCK_LIMIT=${PROCESS_BLOCK_LIMIT:-null}
LOG_FILE=${LOG_FILE:-"hafbe_sync.log"}
BTRACKER_SCHEMA=${BTRACKER_SCHEMA:-"hafbe_bal"}

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
    --stop-at-block=*)
        PROCESS_BLOCK_LIMIT="${1#*=}"
        ;;
    --btracker-schema=*)
        BTRACKER_SCHEMA="${1#*=}"
        ;;
    --log-file=*)
        LOG_FILE="${1#*=}"
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

POSTGRES_ACCESS="postgresql://$POSTGRES_USER@$POSTGRES_HOST:$POSTGRES_PORT/haf_block_log?application_name=block_explorer_block_processing"
# keepalives: a server gone without a reset must end the refresher's session, so it reconnects
VOTES_BY_CAUSE_ACCESS="postgresql://$POSTGRES_USER@$POSTGRES_HOST:$POSTGRES_PORT/haf_block_log?application_name=block_explorer_votes_by_cause&connect_timeout=10&keepalives_idle=60&keepalives_interval=10&keepalives_count=3"
BLOCK_PROCESSING_JOB_PID=0

REGISTRY_PROBE_ATTEMPTS=${REGISTRY_PROBE_ATTEMPTS:-12}
REGISTRY_PROBE_RETRY_SECONDS=${REGISTRY_PROBE_RETRY_SECONDS:-5}

case "$REGISTRY_PROBE_ATTEMPTS" in
    ''|*[!0-9]*|0) echo "ERROR: REGISTRY_PROBE_ATTEMPTS must be a positive number"; exit 1 ;;
esac

# The witness vote change by cause refresher (#211): how often it checks whether a
# refresh is due (one is due about every 100 blocks and at each new UTC day; 0 turns
# the refresher off), and the statement_timeout of each check.
VOTES_BY_CAUSE_CHECK_SECONDS=${VOTES_BY_CAUSE_CHECK_SECONDS:-10}
VOTES_BY_CAUSE_TIMEOUT=${VOTES_BY_CAUSE_TIMEOUT:-5min}

case "$VOTES_BY_CAUSE_CHECK_SECONDS" in
    ''|*[!0-9]*) echo "ERROR: VOTES_BY_CAUSE_CHECK_SECONDS must be a number (0 turns the refresher off)"; exit 1 ;;
esac
if [ "$VOTES_BY_CAUSE_CHECK_SECONDS" -ne 0 ] \
    && ! [[ "$VOTES_BY_CAUSE_TIMEOUT" =~ ^[0-9]+(\.[0-9]+)?[[:space:]]*(us|ms|s|min|h|d)?$ ]]; then
    echo "ERROR: VOTES_BY_CAUSE_TIMEOUT must be a PostgreSQL duration such as 300s or 5min"; exit 1
fi

# Prefixes each line with the time and the refresher's name, on stdout and, unless it
# is STDOUT, appended to the log file (which the driver or the legacy loop writes too).
votes_by_cause_log() {
    local log_file="$1" line
    while IFS= read -r line; do
        line="$(date -u '+%Y-%m-%d %H:%M:%S') votes-by-cause refresher: $line"
        echo "$line"
        [ "$log_file" = STDOUT ] || echo "$line" >> "$log_file"
    done
}

# The witness vote change by cause refresher: one psql session beside block processing
# that asks every VOTES_BY_CAUSE_CHECK_SECONDS whether a refresh is due and makes it
# (hafbe_app.refresh_witness_votes_change_by_cause_in_background), so that a slow
# refresh never holds up a block. Each check is a top-level statement in a REPEATABLE
# READ transaction of its own, under VOTES_BY_CAUSE_TIMEOUT. The session holds the
# shared haf_block_explorer lock, as block processing does, so an install does not run
# under it; client_connection_check_interval ends its backend soon after the container
# is gone. The setup runs with ON_ERROR_STOP: a session that could not take the lock
# (HAF refuses it while it reports the application broken) or set its timeout ends,
# and is retried. It reconnects after a lost connection, and stops once this script's
# process (the driver after the exec) has exited. Checks are written on a clock, so a
# long refresh queues a few; one that is not due costs a lookup.
votes_by_cause_refresher() {
    local parent=$$ log_file="$1"
    set +e +o pipefail
    trap - EXIT TERM
    while kill -0 "$parent" 2>/dev/null; do
        {
            echo '\set ON_ERROR_STOP on'
            echo "SET search_path TO ${BTRACKER_SCHEMA};"
            echo "SET client_connection_check_interval = '10s';"
            echo "DO \$\$ BEGIN IF to_regprocedure('hive.acquire_app_block_processor_locks(text[])') IS NOT NULL THEN PERFORM hive.acquire_app_block_processor_locks(ARRAY['haf_block_explorer']); END IF; END \$\$;"
            echo "SET statement_timeout = '${VOTES_BY_CAUSE_TIMEOUT}';"
            echo '\set ON_ERROR_STOP off'
            while kill -0 "$parent" 2>/dev/null; do
                # A write that fails (psql gone) ends the session, as SIGPIPE would
                printf '%s\n' "BEGIN ISOLATION LEVEL REPEATABLE READ;" \
                    "CALL hafbe_app.refresh_witness_votes_change_by_cause_in_background();" "COMMIT;" || break
                sleep "$VOTES_BY_CAUSE_CHECK_SECONDS"
            done
        } | psql "$VOTES_BY_CAUSE_ACCESS" -X -w -q -o /dev/null 2>&1 | votes_by_cause_log "$log_file"
        kill -0 "$parent" 2>/dev/null || break
        echo "the session ended; reconnecting in 30 s" | votes_by_cause_log "$log_file"
        sleep 30
    done
}

# start_votes_by_cause_refresher <n_blocks> <log_file>: in the background, unless it
# is off or the run is bounded by --stop-at-block (a test or CI run, which refreshes
# the breakdown itself if it needs it).
start_votes_by_cause_refresher() {
    # --stop-at-block=0 means no limit
    if [ "$VOTES_BY_CAUSE_CHECK_SECONDS" -eq 0 ] || { [ "$1" != "null" ] && [ "$1" != "0" ]; }; then
        return
    fi
    echo "Starting the witness vote change by cause refresher (a check every ${VOTES_BY_CAUSE_CHECK_SECONDS} s, statement_timeout ${VOTES_BY_CAUSE_TIMEOUT})"
    votes_by_cause_refresher "$2" &
}

# Asks the HAF application registry who should process the hafbe_app context's blocks.
# The application is registered as haf_block_explorer, the name it locks. Prints one of:
#   driver    registered as haf_block_explorer with an entry procedure that exists
#   broken    registered as haf_block_explorer, but with no entry procedure or one that is
#             gone (e.g. after a failed uninstall)
#   stale     the context is registered under the application's old name, hafbe_app, by an
#             install older than the rename; db/hafbe_app.sql refuses to install over it
#   embedded  another application owns the hafbe_app context and drives it
#   legacy    not in the registry, mostly on a HAF older than the registry (haf#341,
#             1.28.6 and older), where db/hafbe_app.sql skips registration
#
# haf_app_driver.py being on PATH is not enough: the psql base image has shipped it since
# 14-3, and the driver exits before its first range when the registry cannot run the app.
# Under a restart policy that is a container that never processes a block.
#
# Two statements, not one: PostgreSQL resolves relations at plan time, so a query naming
# hafd.applications fails on a HAF without it whatever to_regclass() says. The SQL goes
# through stdin because psql does not substitute :'app' in -c strings. -w: never wait for
# a password on stdin, which holds the SQL.
registry_probe() {
    PGCONNECT_TIMEOUT="${PGCONNECT_TIMEOUT:-5}" \
    psql "$POSTGRES_ACCESS" -X -w -Atq -v ON_ERROR_STOP=on \
        -v app=haf_block_explorer -v old_app=hafbe_app -v context=hafbe_app <<'EOF'
SELECT to_regclass('hafd.applications') IS NOT NULL AS has_registry \gset
\if :has_registry
SELECT CASE
  WHEN EXISTS (
    SELECT 1 FROM hafd.applications
    WHERE name = :'app'
      AND process_procedure IS NOT NULL
      AND to_regprocedure(process_procedure || '(hive.blocks_range)') IS NOT NULL)
  THEN 'driver'
  WHEN EXISTS (SELECT 1 FROM hafd.applications WHERE name = :'app')
  THEN 'broken'
  WHEN EXISTS (
    SELECT 1 FROM hafd.applications
    WHERE name = :'old_app' AND contexts @> ARRAY[ :'context' ]::TEXT[])
  THEN 'stale'
  WHEN EXISTS (
    SELECT 1 FROM hafd.applications
    WHERE name <> :'app' AND contexts @> ARRAY[ :'context' ]::TEXT[])
  THEN 'embedded'
  ELSE 'legacy'
END;
\else
SELECT 'legacy';
\endif
EOF
}

# Sets LOOP to the probe's answer, or to "error" (a query that failed on a live
# connection, e.g. a privilege missing: a retry would not change it) or "unreachable",
# with psql's first error line in PROBE_ERROR. Neither failure falls back to the legacy
# loop: for a context another application drives, that would start a second loop on it.
#
# psql exits 2 when it cannot connect. A database briefly down at start must not decide
# the loop for the container's whole life, so that is retried REGISTRY_PROBE_ATTEMPTS
# times, REGISTRY_PROBE_RETRY_SECONDS apart (about a minute by default); after that the
# restart policy retries. Runs in this shell, not in $( ), so that docker's SIGTERM is
# taken between attempts.
choose_loop() {
    local attempt=0 status errfile
    errfile="$(mktemp)"
    while :; do
        attempt=$((attempt + 1))
        status=0
        LOOP="$(registry_probe 2>"$errfile")" || status=$?
        PROBE_ERROR="$(grep -v '^[[:space:]]*$' "$errfile" | head -n 1 || true)"
        case "$status" in
            0) break ;;
            2) ;;
            *) LOOP="error"; break ;;
        esac
        if [ "$attempt" -ge "$REGISTRY_PROBE_ATTEMPTS" ]; then
            LOOP="unreachable"; break
        fi
        echo "Cannot connect to the database to check the HAF application registry (attempt $attempt of $REGISTRY_PROBE_ATTEMPTS): ${PROBE_ERROR}; retrying"
        sleep "$REGISTRY_PROBE_RETRY_SECONDS" & wait $!
    done
    rm -f "$errfile"
}

# The generic HAF block-processing driver (haf#341) runs the registered
# hafbe_app.process_blocks procedure per delivered range (hafbe_app plus the
# embedded balance tracker context) and idles on its own connection between
# blocks. It ships with the psql base image. exec it from this shell, before the
# cleanup trap and the background job below, so that it takes this process's
# place (PID 1 in the container) and receives SIGTERM itself. The driver writes
# the optional log file and stamps its own timestamps.
run_driver() {
    local n_blocks="$1" log_file="$2"
    local limit_arg=()
    [ "$n_blocks" != "null" ] && limit_arg=(--stop-at-block="$n_blocks")
    date -uIseconds > /tmp/block_processing_startup_time.txt
    start_votes_by_cause_refresher "$n_blocks" "$log_file"
    # the driver appends to the log file itself (STDOUT = none)
    exec haf_app_driver.py --app=haf_block_explorer --postgres-url="$POSTGRES_ACCESS" --lock=haf_block_explorer --log-file="$log_file" "${limit_arg[@]}"
}

# Execs the driver, exits, or returns when the legacy CALL main() loop is the one to run.
select_loop() {
    trap 'exit 143' TERM INT
    choose_loop
    trap - TERM INT
    case "$LOOP" in
        driver)
            if command -v haf_app_driver.py >/dev/null 2>&1; then
                echo "haf_block_explorer is registered in the HAF application registry; running haf_app_driver.py"
                run_driver "$@"
            fi
            echo "WARNING: haf_app_driver.py not found, falling back to the legacy CALL main() loop"
            ;;
        broken)
            echo "ERROR: haf_block_explorer is in the HAF application registry, but its entry procedure"
            echo "       (hafbe_app.process_blocks) is missing. Reinstall haf_block_explorer"
            echo "       (scripts/install_app.sh)."
            exit 1
            ;;
        stale)
            echo "ERROR: the hafbe_app context is registered in the HAF application registry as"
            echo "       application hafbe_app, not haf_block_explorer. Replay haf_block_explorer from"
            echo "       scratch, or run SELECT hive.app_unregister('hafbe_app'); and reinstall"
            echo "       haf_block_explorer (scripts/install_app.sh)."
            exit 1
            ;;
        embedded)
            # Its loop already processes this context; a second one must not.
            echo "ERROR: the hafbe_app context belongs to another application in the HAF application"
            echo "       registry, whose block processing drives it. Not starting a second loop."
            exit 1
            ;;
        error)
            echo "ERROR: could not read the HAF application registry: ${PROBE_ERROR}"
            exit 1
            ;;
        unreachable)
            echo "ERROR: could not connect to the database to check the HAF application registry: ${PROBE_ERROR}"
            exit 1
            ;;
        legacy)
            echo "WARNING: the HAF application registry does not list haf_block_explorer (a HAF older than the"
            echo "         registry, 1.28.6 and older, has none); running the legacy CALL main() loop"
            ;;
        *)
            echo "ERROR: unexpected answer from the HAF application registry probe: '$LOOP'"
            exit 1
            ;;
    esac
}

select_loop "$PROCESS_BLOCK_LIMIT" "$LOG_FILE"

# shellcheck disable=SC2317
cleanup () {
  echo "Performing a cleanup - attempting to trigger app shutdown..."

  psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -c "\timing" -c "SELECT hafbe_app.stopProcessing();"

  echo "hafbe shutdown trigerred."

  echo "Waiting for hafbe block processing finish..."
  [ "$BLOCK_PROCESSING_JOB_PID" -eq 0 ] || wait $BLOCK_PROCESSING_JOB_PID || true
  echo "hafbe block processing finished."

  echo "Cleanup actions done."
}


# https://gist.github.com/CMCDragonkai/e2cde09b688170fb84268cafe7a2b509
# If we do `trap cleanup INT QUIT TERM` directly, then using `exit` command anywhere
# in the script will exit the script without triggering the cleanup
trap 'exit' INT QUIT TERM
trap cleanup EXIT


process_blocks() {
{
    local n_blocks="${1:-null}"
    local log_file="${2:-}"
    echo "Log file: $log_file"

    if command -v ts > /dev/null 2>&1; then
      timestamper="ts '%Y-%m-%d %H:%M:%.S'"
    elif command -v tai64nlocal > /dev/null 2>&1; then
      timestamper="tai64n | tai64nlocal"
    else
      timestamper="cat"
    fi

    # save off the startup time for use in health checks
    date -uIseconds > /tmp/block_processing_startup_time.txt

    if [[ "$log_file" == "STDOUT" ]]; then
        run_with_reconnect.sh -- psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -c "\timing" -c "SET temp_buffers = '16MB';" -c "SET SEARCH_PATH TO ${BTRACKER_SCHEMA};" -c "CALL hafbe_app.main('hafbe_app', '${BTRACKER_SCHEMA}', $n_blocks);"
    else
        run_with_reconnect.sh -- psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -c "\timing" -c "SET temp_buffers = '16MB';" -c "SET SEARCH_PATH TO ${BTRACKER_SCHEMA};" -c "CALL hafbe_app.main('hafbe_app', '${BTRACKER_SCHEMA}', $n_blocks);" 2>&1 | tee -i >(eval "$timestamper" >> "$log_file")
    fi

} &
BLOCK_PROCESSING_JOB_PID=$!

echo "waiting for job finish: $BLOCK_PROCESSING_JOB_PID."
local status=0
wait $BLOCK_PROCESSING_JOB_PID || status=$?
return ${status}
}

start_votes_by_cause_refresher "$PROCESS_BLOCK_LIMIT" "$LOG_FILE"
process_blocks "$PROCESS_BLOCK_LIMIT" "$LOG_FILE"

