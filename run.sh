#!/bin/bash

set -e
set -o pipefail

create_user() {
    psql -a -v "ON_ERROR_STOP=1" -d haf_block_log -c '\timing' -c "call hafbe_backend.create_api_user();"
}

create_api() {
    postgrest_dir=$PWD/api
    psql -a -v "ON_ERROR_STOP=1" -d haf_block_log -f $postgrest_dir/backend.sql
    psql -a -v "ON_ERROR_STOP=1" -d haf_block_log -f $postgrest_dir/endpoints.sql
}

start_webserver() {
    default_port=3000
    if [[ $1 == ?+([0-9]) ]]; then 
        port=$1
    else
        port=$default_port
    fi

    sed -i "/server-port = /s/.*/server-port = \"$port\"/" postgrest.conf
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

if [ "$1" = "start" ]; then
    start_webserver $2
elif [ "$1" = "re-start" ]; then
    create_api
    create_user
    echo 'SUCCESS: Users and API recreated'
    start_webserver $2
elif [ "$1" =  "install-postgrest" ]; then
    install_postgrest
elif [ "$1" =  "install-plpython" ]; then
    install_plpython
else
    echo "job not found"
    exit 1
fi;