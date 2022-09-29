#!/bin/bash

set -e
set -o pipefail

drop_db() {
    psql -d $DB_NAME -c "SELECT hive.app_remove_context('$hive_app_name');"
    psql -d $DB_NAME -c "DROP SCHEMA IF EXISTS hafbe_app CASCADE;"
}

create_db() {
    process_blocks $@
}

process_blocks() {
    n_blocks="${1:-null}"
    psql -a -v "ON_ERROR_STOP=1" -d $DB_NAME -c "\timing" -c "CALL hafbe_app.main('$hive_app_name', $n_blocks);"
}

stop_processing() {
    psql -a -v "ON_ERROR_STOP=1" -d $DB_NAME -c "SELECT hafbe_app.stopProcessing();"
}

continue_processing() {
    psql -a -v "ON_ERROR_STOP=1" -d $DB_NAME -c "SELECT hafbe_app.allowProcessing();"
}

create_api() {
    postgrest_dir=$PWD/api

    psql -a -v "ON_ERROR_STOP=1" -d $DB_NAME -f db/hafbe_app.sql
    psql -a -v "ON_ERROR_STOP=1" -d $DB_NAME -c "\timing" -f db/indexes.sql
    psql -a -v "ON_ERROR_STOP=1" -d $DB_NAME -c "CALL hafbe_app.create_context_if_not_exists('$hive_app_name');"

    psql -a -v "ON_ERROR_STOP=1" -d $DB_NAME -f $postgrest_dir/views.sql
    psql -a -v "ON_ERROR_STOP=1" -d $DB_NAME -f $postgrest_dir/types.sql
    psql -a -v "ON_ERROR_STOP=1" -d $DB_NAME -f $postgrest_dir/exceptions.sql
    psql -a -v "ON_ERROR_STOP=1" -d $DB_NAME -f $postgrest_dir/backend.sql
    psql -a -v "ON_ERROR_STOP=1" -d $DB_NAME -f $postgrest_dir/endpoints.sql
    psql -a -v "ON_ERROR_STOP=1" -d $DB_NAME -f $postgrest_dir/roles.sql

    echo "Creating indexes, this might take a while."
    psql -a -v "ON_ERROR_STOP=1" -d $DB_NAME -c "\timing" -c "SELECT hafbe_indexes.create_haf_indexes()"
}

create_indexes() {
    psql -a -v "ON_ERROR_STOP=1" -d $DB_NAME -c "\timing" -c "SELECT hafbe_indexes.create_hafbe_indexes()"
}

start_webserver() {
    export PGRST_DB_URI="postgres://haf_admin@/haf_block_log"
    export PGRST_DB_SCHEMA="hafbe_endpoints"
    export PGRST_DB_ANON_ROLE="hafbe_user"

    export PGRST_SERVER_PORT=3000
    if [[ $1 == ?+([0-9]) ]]; then 
        export PGRST_SERVER_PORT=$1
    fi

    postgrest
}

install_postgrest() {
    sudo apt-get update -y
    sudo apt-get install wget -y

    postgrest=postgrest-v$postgrest_v-linux-static-x64.tar.xz
    wget https://github.com/PostgREST/postgrest/releases/download/v$postgrest_v/$postgrest

    sudo tar xvf $postgrest -C '/usr/local/bin'
    rm $postgrest
}

install_plpython() {
    sudo apt-get update -y
    sudo apt-get -y install python3 postgresql-plpython3-14
}

install_jmeter() {
    sudo apt-get update -y
    sudo apt-get install openjdk-8-jdk -y

    wget "https://downloads.apache.org//jmeter/binaries/apache-jmeter-${jmeter_v}.zip"

    jmeter_src="apache-jmeter-${jmeter_v}"
    sudo unzip "${jmeter_src}.zip" -d '/usr/local/src'
    rm "${jmeter_src}.zip"

    jmeter="jmeter-${jmeter_v}"
    touch $jmeter
    echo '#!/usr/bin/env bash' >> $jmeter
    echo '' >> $jmeter
    echo "cd '/usr/local/src/apache-jmeter-${jmeter_v}/bin'" >> $jmeter
    echo './jmeter $@' >> $jmeter
    sudo chmod +x $jmeter
    sudo mv $jmeter "/usr/local/bin/${jmeter}"

    sudo chmod 777 /usr/local/src/apache-jmeter-5.4.3/bin/
    sudo chmod 777 /usr/local/src/apache-jmeter-5.4.3/bin/jmeter.log
}

run_tests() {
    server_port=$(sed -rn '/^server-port/p' $CONFIG_PATH | sed "s/server-port//g" | sed "s/[\"\? =]//g")

    bash $PWD/tests/run_performance_tests.sh $server_port $@
}

postgrest_v=9.0.0
jmeter_v=5.4.3

DB_NAME=haf_block_log
CONFIG_PATH=$PWD/postgrest.conf

hive_app_name="hafbe_app"

if [ "$1" = "start" ]; then
    start_webserver $2
elif [ "$1" = "drop-db" ]; then
    drop_db
elif [ "$1" = "create-db" ]; then
    create_db $2
elif [ "$1" = "re-start" ]; then
    create_api
    echo 'SUCCESS: Users and API recreated'
    start_webserver $2
elif [ "$1" =  "create-indexes" ]; then
    create_indexes
elif [ "$1" =  "stop-processing" ]; then
    stop_processing
elif [ "$1" =  "continue-processing" ]; then
    continue_processing
elif [ "$1" =  "install-postgrest" ]; then
    install_postgrest
elif [ "$1" =  "install-plpython" ]; then
    install_plpython
elif [ "$1" =  "install-jmeter" ]; then
    install_jmeter
elif [ "$1" =  "run-tests" ]; then
    run_tests $@
else
    echo "job not found"
    exit 1
fi;
