#!/bin/bash

set -e
set -o pipefail


print_help () {
    echo "Usage: $0 [OPTION[=VALUE]]..."
    echo
    echo "Allows to setup a database already filled by HAF instance, to work with haf_be application."
    echo "OPTIONS:"
    echo "  --c=VALUE                Allows to specify a script command"
    echo "  --host=VALUE             Allows to specify a PostgreSQL host location (defaults to localhost)"
    echo "  --port=NUMBER            Allows to specify a PostgreSQL operating port (defaults to 5432)"
    echo "  --user=VALUE             Allows to specify a PostgreSQL user (defaults to haf_admin)"
    echo "  --limit=VALUE            Allows to specify a limit for processing blocks,"
    echo "                           if --limit=0 hafbe will wait for new blocks (defaults to 0)"
    echo "  --webserver_port=NUMBER  Allows to specify a webserver port (defaults to 3000)"
    echo
    echo "List of available script commands (--c=VALUE) :"
    echo "  setup-all                Setup db and all dependecies"
    echo
    echo "  setup-db                 Setup db only"
    echo
    echo "  start-web                Start postgrest webserver"
    echo
    echo "  process-blocks           Start processing blocks"
    echo
    echo "  continue-processing      "
    echo
    echo "  stop-processing          "
    echo
    echo "  drop-db                  "
    echo
    echo "  create-hafbe-indexes     "
    echo
    echo "  run-tests                "
    echo
}

POSTGRES_HOST="localhost"
POSTGRES_PORT=5432
POSTGRES_USER="haf_admin"
COMMAND=""
PROCESS_BLOCK_LIMIT=0
WEBSERVER_PORT=3000

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
    --c=*)
        COMMAND="${1#*=}"
        ;;
    --limit=*)
        PROCESS_BLOCK_LIMIT="${1#*=}"
        ;;
    --webserver_port=*)
        WEBSERVER_PORT="${1#*=}"
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

POSTGRES_ACCESS_OWNER="postgresql://hafbe_owner@$POSTGRES_HOST:$POSTGRES_PORT/haf_block_log"

process_blocks() {
    n_blocks="${1:-null}"
    log_file="block_processing.log"
    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "\timing" -c "CALL hafbe_app.main('hafbe_app', $n_blocks);" 2>&1 | tee $log_file
}

stop_processing() {
    psql $POSTGRES_ACCESS_OWNER -v "ON_ERROR_STOP=on" -c "SELECT hafbe_app.stopProcessing();"
}

continue_processing() {
    psql $POSTGRES_ACCESS_OWNER -v "ON_ERROR_STOP=on" -c "SELECT hafbe_app.allowProcessing();"
}

drop_db() {
    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "DROP SCHEMA IF EXISTS hafbe_views CASCADE;"
    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "SELECT hive.app_remove_context('hafbe_app');"
    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "DROP SCHEMA IF EXISTS hafbe_app CASCADE;"
    psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "DROP SCHEMA IF EXISTS btracker_app CASCADE;"
}

create_hafbe_indexes() {
    psql $POSTGRES_ACCESS_OWNER -v "ON_ERROR_STOP=on" -c "\timing" -c "SELECT hafbe_indexes.create_hafbe_indexes();"
}

start_webserver() { 
    export PGRST_DB_URI="postgres://hafbe_owner@/haf_block_log"
    export PGRST_DB_SCHEMA="hafbe_endpoints"
    export PGRST_DB_ANON_ROLE="hafbe_user"
    export PGRST_SERVER_PORT=$WEBSERVER_PORT

    postgrest
}

if [[ ! "run-tests start" =~ "$COMMAND" ]]; then
    sudo echo
fi;

if [ "$COMMAND" = "start-web" ]; then
    start_webserver $WEBSERVER_PORT
elif [ "$COMMAND" = "setup-db" ]; then
    ./scripts/setup_db.sh --host=$POSTGRES_HOST --port=$POSTGRES_PORT --user=$POSTGRES_USER
elif [ "$COMMAND" = "setup-all" ]; then
    ./scripts/setup_dependancies.sh
    ./scripts/setup_db.sh --host=$POSTGRES_HOST --port=$POSTGRES_PORT --user=$POSTGRES_USER
elif [ "$COMMAND" = "process-blocks" ]; then
    process_blocks $PROCESS_BLOCK_LIMIT
elif [ "$COMMAND" =  "stop-processing" ]; then
    stop_processing
elif [ "$COMMAND" =  "continue-processing" ]; then
    continue_processing
    process_blocks $PROCESS_BLOCK_LIMIT
elif [ "$COMMAND" = "drop-db" ]; then
    drop_db
elif [ "$COMMAND" =  "create-hafbe-indexes" ]; then
    create_hafbe_indexes
elif [ "$COMMAND" =  "run-tests" ]; then
    bash $PWD/tests/run_performance_tests.sh $@
else
    echo "job not found"
    exit 1
fi;