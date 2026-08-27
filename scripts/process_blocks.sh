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
BLOCK_PROCESSING_JOB_PID=0

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

    # The generic HAF block-processing driver (haf#341) runs the registered
    # hafbe_app.process_blocks procedure per delivered range (hafbe_app plus the
    # embedded balance tracker context) and idles on its own connection between
    # blocks. It ships with the psql base image. exec it directly so that it is
    # PID 1 and receives SIGTERM itself (a bash parent would swallow it until
    # docker's kill); the optional log file is fed through a process substitution,
    # which survives the exec. The driver stamps its own timestamps.
    if command -v haf_app_driver.py >/dev/null 2>&1; then
        trap - EXIT INT QUIT TERM
        local limit_arg=()
        [ "$n_blocks" != "null" ] && limit_arg=(--stop-at-block="$n_blocks")
        date -uIseconds > /tmp/block_processing_startup_time.txt
        if [[ "$log_file" == "STDOUT" ]]; then
            exec haf_app_driver.py --app=hafbe_app --postgres-url="$POSTGRES_ACCESS" --lock=haf_block_explorer "${limit_arg[@]}"
        else
            exec haf_app_driver.py --app=hafbe_app --postgres-url="$POSTGRES_ACCESS" --lock=haf_block_explorer "${limit_arg[@]}" > >(tee -i "$log_file") 2>&1
        fi
    fi
    echo "WARNING: haf_app_driver.py not found, falling back to the legacy CALL main() loop"

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
        run_with_reconnect.sh -- psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -c "\timing" -c "SET temp_buffers = '16MB';" -c "SET SEARCH_PATH TO ${BTRACKER_SCHEMA};" -c "CALL hafbe_app.main('hafbe_app', '${BTRACKER_SCHEMA}', $n_blocks);" 2>&1 | tee -i >(eval "$timestamper" > "$log_file")
    fi

} &
BLOCK_PROCESSING_JOB_PID=$!

jobs -l

echo "waiting for job finish: $BLOCK_PROCESSING_JOB_PID."
local status=0
wait $BLOCK_PROCESSING_JOB_PID || status=$?
return ${status}
}

process_blocks "$PROCESS_BLOCK_LIMIT" "$LOG_FILE"

