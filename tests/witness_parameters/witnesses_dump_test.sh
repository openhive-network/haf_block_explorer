#! /bin/bash


set -euo pipefail

SCRIPTDIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"


POSTGRES_HOST="localhost"
POSTGRES_PORT=5432
POSTGRES_USER="hafbe_owner"
BTRACKER_SCHEMA="hafbe_bal"

print_help () {
    echo "Usage: $0 [OPTION[=VALUE]]..."
    echo
    echo "Allows to setup a database already filled by HAF instance, to work with haf_be application."
    echo "OPTIONS:"
    echo "  --host=VALUE             Allows to specify a PostgreSQL host location (defaults to localhost)"
    echo "  --port=NUMBER            Allows to specify a PostgreSQL operating port (defaults to 5432)"
    echo "  --user=VALUE             Allows to specify a PostgreSQL user (defaults to hafbe_owner)"
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

echo "Clearing tables..."
psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "TRUNCATE hafbe_backend.witness_props;"
psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "TRUNCATE hafbe_backend.differing_witnesses;"

# CI comes with psycopg2 preinstalled
if [[ -z "${CI:-}" ]]; then
    echo "Installing dependecies..."
    pip install psycopg2-binary
fi

rm -f "${SCRIPTDIR}/accounts_dump.json"
# The line below is somewhat problematic. Gunzip by default deletes gz file after decompression,
# but the '-k' parameter, which prevents that from happening is not supported on some of its versions.
# 
# Thus, depending on the OS, the line below may need to be replaced with one of the following:
# gunzip -c "${SCRIPTDIR}/accounts_dump.json.gz" > "${SCRIPTDIR}/accounts_dump.json"
# gzcat "${SCRIPTDIR}/accounts_dump.json.gz" > "${SCRIPTDIR}/accounts_dump.json"
# zcat "${SCRIPTDIR}/accounts_dump.json.gz" > "${SCRIPTDIR}/accounts_dump.json"
gunzip -k "${SCRIPTDIR}/accounts_dump.json.gz"

echo "Starting data_insertion_script.py..."
python3 ../../account_dump/data_insertion_script.py "$SCRIPTDIR" --host "$POSTGRES_HOST" --port "$POSTGRES_PORT" --user "$POSTGRES_USER" --type "witness"

echo "Looking for diffrences between hived node and hafbe stats..."

if command -v ts > /dev/null 2>&1; then
    timestamper="ts '%Y-%m-%d %H:%M:%.S'"
elif command -v tai64nlocal > /dev/null 2>&1; then
    timestamper="tai64n | tai64nlocal"
else
    timestamper="cat"
fi

psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -c "SET SEARCH_PATH TO ${BTRACKER_SCHEMA}; SELECT hafbe_backend.compare_witnesses();" 2>&1 | tee -i >(eval "$timestamper" > "witness_dump_test.log")

DIFFERING_ACCOUNTS=$(psql "$POSTGRES_ACCESS_ADMIN" -v "ON_ERROR_STOP=on" -t -A  -c "SELECT * FROM hafbe_backend.differing_witnesses;")

if [ -z "$DIFFERING_ACCOUNTS" ]; then
    echo "Witness properties are correct!"
    exit 0
else
    echo "Witness properties are incorrect..."
    exit 3
fi
