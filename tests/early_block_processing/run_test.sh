#!/usr/bin/env bash
# =============================================================================
# HAF Block Explorer: block processing while hived replays
# =============================================================================
#
# Runs early_block_processing.sql against a synced database whose hafbe_app is
# still in its massive sync, as a role that may update hafd tables (haf_admin):
# the hafbe_app context group starts while hived replays with
# psql-massive-index-policy=keep-monotonic, not with drop-all, and the
# account_ops_count fill waits for the hafd.account_operations indexes.
# Everything it changes is rolled back.
#
# EXIT CODES:
#   0 - Passed, or skipped: HAF has no massive-sync index policy (before haf#379)
#   1 - Failed
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_USER="${POSTGRES_USER:-haf_admin}"
POSTGRES_DATABASE="${POSTGRES_DATABASE:-haf_block_log}"

print_help() {
    cat <<EOF
Usage: $0 [OPTIONS]

Checks that HAF Block Explorer processes blocks while hived replays.

OPTIONS:
    --host=HOSTNAME     PostgreSQL hostname (default: localhost)
    --port=NUMBER       PostgreSQL port (default: 5432)
    --user=USERNAME     PostgreSQL user (default: haf_admin)
    --database=NAME     Database name (default: haf_block_log)
    --help              Show this help message
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

has_policy="$(psql "$POSTGRES_ACCESS" -v ON_ERROR_STOP=on -Atc \
    "SELECT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema = 'hafd' AND table_name = 'indexes_constraints'
                      AND column_name = 'massive_sync_class')")"
if [ "$has_policy" != t ]; then
    echo "SKIPPED: this HAF has no massive-sync index policy (hafd.indexes_constraints.massive_sync_class)"
    exit 0
fi

if ! output="$(psql "$POSTGRES_ACCESS" -v ON_ERROR_STOP=on -f "$SCRIPT_DIR/early_block_processing.sql" 2>&1)"; then
    echo "$output"
    echo "FAILED"
    exit 1
fi
echo "$output"

if ! grep -qF "Waiting for core indexes of hafd.account_operations" <<<"$output"; then
    echo "FAILED: finalize_account_ops_count did not wait for the hafd.account_operations indexes"
    exit 1
fi
echo "PASSED"
