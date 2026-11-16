#!/usr/bin/env bash
# =============================================================================
# HAF Block Explorer: witness vote change by cause
# =============================================================================
#
# Runs witness_votes_change_by_cause.sql against a database with hafbe synced: a
# window of synthetic events applied through hafbe's vote and proxy parsers (every
# cause, proxy switches, two- and four-level chains, a vote followed by a
# power-down) checked against hand-derived values; every witness's total reconciled
# with the change of its votes recomputed from the history; a refresh over the whole
# chain (totals the sums of their causes, rank_start of the refresh's block); and a
# failing refresh contained. The power-up, proxy cascade, expiry and decline events
# need a role that may write hafd.operations (haf_admin); otherwise the output says
# they were skipped. The role must be a member of hafbe_owner. Everything it changes
# is rolled back.
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
POSTGRES_URL=""
BTRACKER_SCHEMA="${BTRACKER_SCHEMA:-hafbe_bal}"

print_help() {
    cat <<EOH
Usage: $0 [OPTIONS]

Checks HAF Block Explorer's witness vote change by cause on synthetic events.

OPTIONS:
    --host=HOSTNAME        PostgreSQL hostname (default: localhost)
    --port=NUMBER          PostgreSQL port (default: 5432)
    --user=USERNAME        PostgreSQL user (default: haf_admin)
    --database=NAME        Database name (default: haf_block_log)
    --url=URL              Full PostgreSQL URL (overrides the above)
    --btracker-schema=NAME Balance tracker schema (default: hafbe_bal)
    --help                 Show this help message
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
        --url=*)
            POSTGRES_URL="${1#*=}"
            ;;
        --btracker-schema=*)
            BTRACKER_SCHEMA="${1#*=}"
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

POSTGRES_ACCESS="${POSTGRES_URL:-postgresql://$POSTGRES_USER@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DATABASE}"

# The vest queries read the balance tracker's tables unqualified, as in production.
if ! output="$(PGOPTIONS="-c search_path=${BTRACKER_SCHEMA},public" \
        psql "$POSTGRES_ACCESS" -v ON_ERROR_STOP=on -f "$SCRIPT_DIR/witness_votes_change_by_cause.sql" 2>&1)"; then
    echo "$output"
    echo "FAILED"
    exit 1
fi
echo "$output"
echo "PASSED"
