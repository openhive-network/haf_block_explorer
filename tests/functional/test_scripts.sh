#! /bin/bash


set -euo pipefail

SCRIPTDIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

POSTGRES_HOST="localhost"
POSTGRES_PORT=5432
POSTGRES_USER="haf_admin"
script_dir="$SCRIPTDIR/../../scripts"

print_help () {
    echo "Usage: $0 [OPTION[=VALUE]]..."
    echo
    echo "Allows to start a reputation tracker test (5m blocks)."
    echo "reputation tracker must be stopped on 5m blocks (add flag to ./process_blocks.sh --stop-at-block=5000000)"
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

pushd "$script_dir"

echo "Test 1. Reinstall app..."
./install_app.sh --host="$POSTGRES_HOST"
echo "Reinstall completed successfully"

echo "Test 2. Uninstall app, leave indexes..."
./uninstall_app.sh --host="$POSTGRES_HOST"
echo "Uninstall app completed successfully"

echo "Test 3. Clear indexes..."
./uninstall_app.sh --host="$POSTGRES_HOST" --drop-indexes
echo "Uninstall app and clear indexes completed successfully"

popd
