#!/usr/bin/env bash
# =============================================================================
# HAF Block Explorer: incremental witness vote cache refresh
# =============================================================================
#
# Runs witness_votes_cache.sql against a database with hafbe synced and its witness
# vote caches filled, as a role that may write hafd.operations and the balance
# tracker's tables (haf_admin): the incremental refresh of an ordinary block, a fork,
# a restart gap, remove_proposal, a new witness, a moved daily-change window and a
# routed vesting withdrawal, each compared against a full recompute. Everything it
# changes is rolled back. Then compare_script_test.sh runs
# scripts/compare_witness_votes_cache.sh in the states it must skip, match and differ
# in, and undoes them.
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

Checks HAF Block Explorer's incremental witness vote cache refresh against a full recompute.

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
        psql "$POSTGRES_ACCESS" -v ON_ERROR_STOP=on -f "$SCRIPT_DIR/witness_votes_cache.sql" 2>&1)"; then
    echo "$output"
    echo "FAILED"
    exit 1
fi
echo "$output"

if ! "$SCRIPT_DIR/compare_script_test.sh" --url="$POSTGRES_ACCESS" --btracker-schema="$BTRACKER_SCHEMA"; then
    echo "FAILED"
    exit 1
fi
echo "PASSED"
