#!/usr/bin/env bash
# =============================================================================
# HAF Block Explorer: protocol HBD debt ratio of /hbd/status (#153)
# =============================================================================
#
# Runs hbd_protocol_ratio.sql against a database with hafbe installed and synced past
# block 4,600,000 without HF24 (the CI mainnet chain), as a role that may write hafd
# tables (haf_admin): the ratio formula against hived's own computation, and the endpoint
# with HF24 and a treasury faked mid-chain. Everything it changes is rolled back.
#
# EXIT CODES:
#   0 - Passed
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

Checks the protocol HBD debt ratio of HAF Block Explorer's /hbd/status.

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

if ! output="$(psql "$POSTGRES_ACCESS" -v ON_ERROR_STOP=on -f "$SCRIPT_DIR/hbd_protocol_ratio.sql" 2>&1)"; then
    echo "$output"
    echo "FAILED"
    exit 1
fi
echo "$output"
echo "PASSED"
