#!/usr/bin/env bash
# =============================================================================
# HAF Block Explorer: visibility map after the massive sync
# =============================================================================
#
# Runs post_sync_freeze.sql against a database with hafbe installed, as a role
# that may write hafd.vacuum_requests (haf_admin): the install's autovacuum
# reloptions and the 'freeze' requests of hafbe_app.request_tables_freeze().
# Everything it changes is rolled back.
#
# EXIT CODES:
#   0 - Passed, or skipped: HAF has no vacuum request kinds (before haf#360)
#   1 - Failed
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_USER="${POSTGRES_USER:-haf_admin}"
POSTGRES_DATABASE="${POSTGRES_DATABASE:-haf_block_log}"

print_help() {
    cat <<EOH
Usage: $0 [OPTIONS]

Checks HAF Block Explorer's autovacuum reloptions and post-sync freeze requests.

OPTIONS:
    --host=HOSTNAME     PostgreSQL hostname (default: localhost)
    --port=NUMBER       PostgreSQL port (default: 5432)
    --user=USERNAME     PostgreSQL user (default: haf_admin)
    --database=NAME     Database name (default: haf_block_log)
    --help              Show this help message
EOH
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
        --database=*)
            POSTGRES_DATABASE="${1#*=}"
            ;;
        --help|-h)
            print_help
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1"
            print_help
            exit 1
            ;;
    esac
    shift
done

POSTGRES_ACCESS="postgresql://$POSTGRES_USER@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DATABASE"

has_kinds="$(psql "$POSTGRES_ACCESS" -v ON_ERROR_STOP=on -Atc \
    "SELECT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema = 'hafd' AND table_name = 'vacuum_requests'
                      AND column_name = 'kind')")"
if [ "$has_kinds" != t ]; then
    echo "SKIPPED: this HAF has no vacuum request kinds (hafd.vacuum_requests.kind)"
    exit 0
fi

if ! output="$(psql "$POSTGRES_ACCESS" -v ON_ERROR_STOP=on -f "$SCRIPT_DIR/post_sync_freeze.sql" 2>&1)"; then
    echo "$output"
    echo "FAILED"
    exit 1
fi
echo "$output"
echo "PASSED"
