#! /bin/bash

set -euo pipefail

SCRIPTDIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"


POSTGRES_HOST="localhost"
POSTGRES_PORT=5432
POSTGRES_USER="haf_admin"

print_help () {
cat <<EOF
  Usage: $0 [OPTION[=VALUE]]...

  Dumps accounts.
  OPTIONS:
    --host=VALUE             PostgreSQL host location (defaults to localhost)
    --port=NUMBER            PostgreSQL operating port (defaults to 5432)
    --user=VALUE             PostgreSQL user (defaults to haf_admin)
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

POSTGRES_ACCESS_ADMIN="postgresql://$POSTGRES_USER@$POSTGRES_HOST:$POSTGRES_PORT/haf_block_log"

prepare_data() {
    curl -s -o "$SCRIPTDIR/../account_dump/accounts_dump.json" \
        --data "{\"jsonrpc\":\"2.0\", \"method\":\"database_api.list_accounts\", \"params\": {\"start\":\"\", \"limit\":10000000, \"order\":\"by_name\"}, \"id\":1}" \
        "http://$POSTGRES_HOST:8091"

    echo "Start splitting..."
    split -b 1G "$SCRIPTDIR/../account_dump/accounts_dump.json" chunk
    for file in chunk*; do
        sed -i "s/'//g" "$file"
    done

    rm "$SCRIPTDIR/../account_dump/accounts_dump.json"
    cat chunk* > "$SCRIPTDIR/../account_dump/accounts_dump.json"
    rm chunk*
}

if [ -f "$SCRIPTDIR/../account_dump/accounts_dump.json" ]; then

    echo "Starting data_insertion_stript.py..."
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "TRUNCATE hafbe_backend.account_balances;"
    pip install psycopg2-binary
    python3 ../account_dump/data_insertion_script.py "$SCRIPTDIR/../dump_accounts" --host "$POSTGRES_HOST" --port "$POSTGRES_PORT" --user "$POSTGRES_USER"
    echo "Looking for diffrences between hived node and hafbe stats..."
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "TRUNCATE hafbe_backend.differing_accounts;"
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "SELECT hafbe_backend.compare_accounts();"
    
else

    echo "Starting prepare_data..."
    prepare_data

    echo "Starting data_insertion_stript.py..."
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "TRUNCATE hafbe_backend.account_balances;"
    pip install psycopg2
    python3 ../account_dump/data_insertion_script.py "$SCRIPTDIR/../dump_accounts" --host "$POSTGRES_HOST" --port "$POSTGRES_PORT" --user "$POSTGRES_USER"

    echo "Looking for diffrences between hived node and hafbe stats..."
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "TRUNCATE hafbe_backend.differing_accounts;"
    psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "SELECT hafbe_backend.compare_accounts();"
fi
