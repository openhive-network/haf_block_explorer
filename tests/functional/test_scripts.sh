#! /bin/bash


set -xeuo pipefail

SCRIPTDIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

POSTGRES_HOST="localhost"
script_dir="$SCRIPTDIR/../../scripts"

EXECUTOR_SCRIPT=""

print_help () {
    echo "Usage: $0 [OPTION[=VALUE]]..."
    echo
    echo "Allows to start a haf_block_explorer test (5m blocks)."
    echo "haf_block_explorer must be stopped on 5m blocks (add flag to ./process_blocks.sh --stop-at-block=5000000)"
    echo "OPTIONS:"
    echo "  --host=VALUE                Allows to specify a PostgreSQL host location (defaults to localhost)"
    echo "  --cmd-executor-script=path  Obligatory option to pass tested image entrypoint script, which next will be called with proper arguments in each testing scenario"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --cmd-executor-script=*)
        EXECUTOR_SCRIPT="${1#*=}"
        ;;
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

_TST_EXECUTOR_SCRIPT=${EXECUTOR_SCRIPT:?"Missing --cmd-executor-script arg to specify executor script"}

test_scenario() {
  export POSTGRES_HOST="${POSTGRES_HOST}" # there is no other way to pass postgres host to entrypoint :-(

  "${EXECUTOR_SCRIPT}" "$@"
}

pushd "$script_dir"

echo "Test 1. Reinstall app..."
test_scenario "install_app"
echo "Reinstall completed successfully"

echo "Test 2. Uninstall app, leave indexes..."
test_scenario "uninstall_app"
echo "Uninstall app completed successfully"

echo "Test 3. Clear indexes..."
test_scenario "uninstall_app" --drop-indexes
echo "Uninstall app and clear indexes completed successfully"

popd
