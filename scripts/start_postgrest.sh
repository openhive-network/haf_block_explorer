#!/bin/bash

set -e
set -o pipefail

POSTGRES_HOST="localhost"
POSTGRES_PORT=5432
POSTGRES_USER="hafbe_owner"
WEBSERVER_PORT=3000
ADMIN_PORT=3001

print_help () {
cat <<EOF
  Usage: $0 [OPTION[=VALUE]]...

  Starts up a PostgREST server.
  OPTIONS:
    --host=VALUE             PostgreSQL host location (defaults to localhost)
    --port=NUMBER            PostgreSQL operating port (defaults to 5432)
    --user=VALUE             PostgreSQL user (defaults to haf_admin)
    --webserver-port=VALUE   PostgREST port (defaults to 3000)
    --admin-port=VALUE       PostgREST admin port (defaults to 3001)
EOF
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
    --webserver_port|--webserver-port=*)
        WEBSERVER_PORT="${1#*=}"
        ;;
    --admin_port|--admin-port=*)
        ADMIN_PORT="${1#*=}"
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

start_webserver() { 
    export PGRST_DB_URI="postgres://$POSTGRES_USER@$POSTGRES_HOST:$POSTGRES_PORT/haf_block_log"
    export PGRST_SERVER_PORT=$WEBSERVER_PORT
    export PGRST_ADMIN_SERVER_PORT=$ADMIN_PORT

    postgrest postgrest.conf
}

start_webserver
