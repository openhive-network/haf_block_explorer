#!/usr/bin/env bash
# =============================================================================
# HAFBE Proposal Mock Data Verification
# =============================================================================
#
# Run AFTER:
#   1. ./tests/mocks/install_mock_data.sh   (loads fixtures + rewinds contexts)
#   2. ./scripts/process_blocks.sh ...      (processes the mock range)
#
# Refreshes the two LIVE-mode caches (witness_votes_cache and
# proposal_vote_stats_cache) — they normally refresh per-block while LIVE,
# but if processing stopped mid-batch we force a refresh here — then runs
# tests/mocks/sql/verify.sql which prints a PASS/FAIL table and RAISEs on
# any failure (psql -v ON_ERROR_STOP=on propagates non-zero exit so CI
# fails the job).
#
# Usage:
#   ./verify_mock_data.sh [OPTIONS]
#
# Options:
#   --host=HOSTNAME    PostgreSQL hostname  (default: localhost)
#   --port=PORT        PostgreSQL port      (default: 5432)
#   --user=USERNAME    PostgreSQL user      (default: haf_admin)
#   --url=URL          Full PostgreSQL URL  (overrides above)
#   --help, -h         This help
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HAFBE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MOCKS_DIR="$HAFBE_DIR/tests/mocks"

POSTGRES_USER="${POSTGRES_USER:-haf_admin}"
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_URL="${POSTGRES_URL:-}"

print_help() {
  sed -n '2,/^# =\+$/p' "$0" | sed 's/^# \?//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --host=*)    POSTGRES_HOST="${1#*=}" ;;
    --port=*)    POSTGRES_PORT="${1#*=}" ;;
    --user=*)    POSTGRES_USER="${1#*=}" ;;
    --url=*)     POSTGRES_URL="${1#*=}" ;;
    --help|-h)   print_help; exit 0 ;;
    *) echo "ERROR: unknown arg: $1"; exit 1 ;;
  esac
  shift
done

POSTGRES_ACCESS="${POSTGRES_URL:-postgresql://$POSTGRES_USER@$POSTGRES_HOST:$POSTGRES_PORT/haf_block_log?application_name=hafbe_mock_verify}"
BTRACKER_SCHEMA="${BTRACKER_SCHEMA:-hafbe_bal}"

# btracker_backend.nai_vests() references `asset_table` unqualified — that
# table lives in the btracker schema. Mirrors scripts/install_app.sh.
export PGOPTIONS="-c search_path=${BTRACKER_SCHEMA},public"

run_psql() { psql "$POSTGRES_ACCESS" -v ON_ERROR_STOP=on "$@"; }

echo "=============================================="
echo "HAFBE proposal mock verification"
echo "  Host: $POSTGRES_HOST:$POSTGRES_PORT  User: $POSTGRES_USER"
echo "=============================================="

echo "Step 1: Refreshing vote caches (witness first, then proposal)..."
run_psql -c "SELECT hafbe_app.process_witness_votes_cache()"
run_psql -c "SELECT hafbe_app.process_proposal_vote_stats_cache()"

echo "Step 2: Running verify.sql..."
run_psql -f "$MOCKS_DIR/sql/verify.sql"
