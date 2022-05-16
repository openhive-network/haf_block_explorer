#!/bin/bash

set -e
set -o pipefail

create_api() {
    postgrest_dir=$PWD/api
    psql -a -v "ON_ERROR_STOP=1" -d haf_block_log -f $postgrest_dir/backend.sql
    psql -a -v "ON_ERROR_STOP=1" -d haf_block_log -f $postgrest_dir/endpoints.sql
    psql -a -v "ON_ERROR_STOP=1" -d haf_block_log -f $postgrest_dir/exceptions.sql
    psql -a -v "ON_ERROR_STOP=1" -d haf_block_log -f $postgrest_dir/roles.sql
}

start_webserver() {
    default_port=3000
    if [[ $1 == ?+([0-9]) ]]; then 
        port=$1
    else
        port=$default_port
    fi

    sed -i "/server-port = /s/.*/server-port = \"$port\"/" $CONFIG_PATH
    postgrest postgrest.conf
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
    sudo apt-get -y install python3 postgresql-plpython3-12
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

CONFIG_PATH=$PWD/postgrest.conf

if [ "$1" = "start" ]; then
    start_webserver $2
elif [ "$1" = "re-start" ]; then
    create_api
    echo 'SUCCESS: Users and API recreated'
    start_webserver $2
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