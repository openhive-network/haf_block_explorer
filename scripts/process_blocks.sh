#!/bin/bash

set -e
set -o pipefail


print_help () {
cat <<EOF
    Usage: $0 [OPTION[=VALUE]]...

    Processes blocks using Haf Block Explorer
    OPTIONS:
      --host=HOST             PostgreSQL host (defaults to localhost)
      --port=PORT             PostgreSQL operating port (defaults to 5432)
      --user=USER             PostgreSQL username (defaults to hafbe_owner)
      --limit=LIMIT           Max number of blocks to process (0 for infinite, defaults to 0)
      --log-file              Log file location (defaults to hafbe_sync.log, set to 'STDOUT' to log to STDOUT only)
EOF
}

POSTGRES_HOST=${POSTGRES_HOST:-"localhost"}
POSTGRES_PORT=${POSTGRES_PORT:-5432}
POSTGRES_USER=${POSTGRES_USER:-"hafbe_owner"}
PROCESS_BLOCK_LIMIT=${PROCESS_BLOCK_LIMIT:-0}
LOG_FILE=${LOG_FILE:-"hafbe_sync.log"}

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
    --limit=*)
        PROCESS_BLOCK_LIMIT="${1#*=}"
        ;;
    --log-file=*)
        LOG_FILE="${1#*=}"
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

POSTGRES_ACCESS="postgresql://$POSTGRES_USER@$POSTGRES_HOST:$POSTGRES_PORT/haf_block_log"

process_blocks() {
    local n_blocks="${1:-null}"
    local log_file="${2:-}"
    echo "Log file: $log_file"
    if [[ "$log_file" == "STDOUT" ]]; then
        psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -c "\timing" -c "CALL hafbe_app.main('hafbe_app', 'btracker_app', $n_blocks);"
    else
        psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -c "\timing" -c "CALL hafbe_app.main('hafbe_app', 'btracker_app', $n_blocks);" 2>&1 | ts '%Y-%m-%d %H:%M:%.S' | tee -i "$log_file"
    fi
}

process_blocks "$PROCESS_BLOCK_LIMIT" "$LOG_FILE"