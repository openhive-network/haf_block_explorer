#!/bin/bash

set -e
set -o pipefail

SCRIPTDIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
POSTGRES_HOST="localhost"
POSTGRES_PORT=5432
POSTGRES_USER="hafbe_owner"
WEBSERVER_PORT=3000

SERVER_URL="localhost"
SWAGGER="OFF"
SWAGGER_PORT=8070

print_help () {
    echo "Usage: $0 [OPTION[=VALUE]]..."
    echo
    echo "Allows to setup a database already filled by HAF instance, to work with haf_be application."
    echo "OPTIONS:"
    echo "  --host=VALUE             Allows to specify a PostgreSQL host location (defaults to localhost)"
    echo "  --port=NUMBER            Allows to specify a PostgreSQL operating port (defaults to 5432)"
    echo "  --user=VALUE             Allows to specify a PostgreSQL user (defaults to haf_admin)"
    echo "  --webserver_port=VALUE   Allows to specify a postgrest port (defaults to 3000)"
    echo "  --swagger=ON/OFF         When set to ON, swagger toolset is setup with postgrest (default OFF)"
    echo "                           Used in browser on server_url:swagger_port"
    echo ""
    echo "  --swagger_port=VALUE     Allows to specify a swagger port, (must be specified with swagger ON, default 8070):"
    echo "  --server_url=VALUE    Allows to specify a server url, (must be specified with swagger ON, default localhost):"

}

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
    --webserver_port=*)
        WEBSERVER_PORT="${1#*=}"
        ;;
    --swagger_port=*)
        SWAGGER_PORT="${1#*=}"
        ;;
    --server_url=*)
        SERVER_URL="${1#*=}"
        ;;
    --swagger=*)
        SWAGGER="${1#*=}"
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
PROXY_URL="$SERVER_URL:$WEBSERVER_PORT"

start_webserver() { 
export PGRST_DB_URI=$POSTGRES_ACCESS_ADMIN
export PGRST_DB_SCHEMA="hafbe_endpoints"
export PGRST_DB_ANON_ROLE="hafbe_user"
export PGRST_SERVER_PORT=$WEBSERVER_PORT
export PGRST_OPENAPI_SERVER_PROXY_URI=$PROXY_URL

if [[ "$SWAGGER" == "ON" ]]; then
    docker run -d -e \
    API_URL=$PROXY_URL \
    -p $SWAGGER_PORT:8080 \
    swaggerapi/swagger-ui
fi

postgrest
}

start_webserver
