#!/bin/bash

set -e
set -o pipefail

process_blocks() {
    n_blocks="${1:-null}"
    log_file="block_processing.log"
    sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -c "\timing" -c "CALL hafbe_app.main('hafbe_app', $n_blocks);" 2>&1 | tee $log_file
}

stop_processing() {
    sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -c "SELECT hafbe_app.stopProcessing();"
}

continue_processing() {
    sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -c "SELECT hafbe_app.allowProcessing();"
}

drop_db() {
    sudo -nu $admin_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -c "SELECT hive.app_remove_context('hafbe_app');"
    sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -c "DROP SCHEMA IF EXISTS hafbe_app CASCADE;"
}

create_hafbe_indexes() {
    sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -c "\timing" -c "SELECT hafbe_indexes.create_hafbe_indexes();"
}

start_webserver() {
    export PGRST_DB_URI="postgres://hafbe_owner@/haf_block_log"
    export PGRST_DB_SCHEMA="hafbe_endpoints"
    export PGRST_DB_ANON_ROLE="hafbe_user"

    export PGRST_SERVER_PORT=3000
    if [[ $1 == ?+([0-9]) ]]; then 
        export PGRST_SERVER_PORT=$1
    fi

    postgrest
}

DB_NAME=haf_block_log
owner_role=hafbe_owner
admin_role=haf_admin

if [ "$1" != "start" ]; then
    sudo echo
fi;

if [ "$1" = "start" ]; then
    start_webserver $2
elif [ "$1" = "setup" ]; then
    ./scripts/setup_dependancies.sh all
    ./scripts/setup_db.sh all
elif [ "$1" = "process-blocks" ]; then
    process_blocks $2
elif [ "$1" =  "stop-processing" ]; then
    stop_processing
elif [ "$1" =  "continue-processing" ]; then
    continue_processing
    process_blocks $2
elif [ "$1" = "drop-db" ]; then
    drop_db
elif [ "$1" =  "create-hafbe-indexes" ]; then
    create_hafbe_indexes
elif [ "$1" =  "run-tests" ]; then
    bash $PWD/tests/run_performance_tests.sh $@
else
    echo "job not found"
    exit 1
fi;