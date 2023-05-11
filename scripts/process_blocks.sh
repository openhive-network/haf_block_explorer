#!/bin/bash

set -e
set -o pipefail


print_help () {
    echo "Usage: $0 [OPTION[=VALUE]]..."
    echo
    echo "Allows to setup a database already filled by HAF instance, to work with haf_be application."
    echo "OPTIONS:"
    echo "  --host=VALUE             Allows to specify a PostgreSQL host location (defaults to localhost)"
    echo "  --port=NUMBER            Allows to specify a PostgreSQL operating port (defaults to 5432)"
    echo "  --user=VALUE             Allows to specify a PostgreSQL user (defaults to haf_admin)"
    echo "  --limit=VALUE            Allows to specify a limit for processing blocks,"
}

POSTGRES_HOST="localhost"
POSTGRES_PORT=5432
POSTGRES_USER="haf_admin"
PROCESS_BLOCK_LIMIT=0

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

POSTGRES_ACCESS_ADMIN="postgresql://$POSTGRES_USER@$POSTGRES_HOST:$POSTGRES_PORT/haf_block_log"

process_blocks() {
    n_blocks="${1:-null}"
    log_file="block_processing.log"
    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "\timing" -c "CALL hafbe_app.main('hafbe_app', $n_blocks);" 2>&1 | tee $log_file
}

process_blocks $PROCESS_BLOCK_LIMIT