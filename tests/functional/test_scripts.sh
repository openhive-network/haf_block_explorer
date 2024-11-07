#! /bin/bash


set -euo pipefail

SCRIPTDIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

POSTGRES_HOST="localhost"
script_dir="$SCRIPTDIR/../../scripts"

print_help () {
    echo "Usage: $0 [OPTION[=VALUE]]..."
    echo
    echo "Allows to start a haf_block_explorer test (5m blocks)."
    echo "haf_block_explorer must be stopped on 5m blocks (add flag to ./process_blocks.sh --stop-at-block=5000000)"
    echo "OPTIONS:"
    echo "  --host=VALUE             Allows to specify a PostgreSQL host location (defaults to localhost)"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --host=*)
        POSTGRES_HOST="${1#*=}"
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
