#!/usr/bin/env bash
# =============================================================================
# HAFBE Proposal Mock Data Installation
# =============================================================================
#
# Loads mock proposal blockchain data (block headers + ops) into the HAF
# database and rewinds the hafbe_app / hafbe_bal contexts so the mock range
# becomes the next processable batch. Does NOT process the blocks itself.
#
# Block range: 91000000+ (chosen to NOT collide with btracker's 90000000+).
#
# Workflow:
#   1. ./tests/mocks/install_mock_data.sh           # load fixtures
#   2. ./scripts/process_blocks.sh --stop-at-block=91000006
#                                                   # process mock range
#   3. ./scripts/verify_mock_data.sh                # assert final state
#
# Usage:
#   ./install_mock_data.sh [OPTIONS]
#
# Options:
#   --host=HOSTNAME    PostgreSQL hostname  (default: localhost)
#   --port=PORT        PostgreSQL port      (default: 5432)
#   --user=USERNAME    PostgreSQL user      (default: haf_admin)
#   --url=URL          Full PostgreSQL URL  (overrides above)
#   --help, -h         This help
#
# Prerequisites:
#   - HAF database running and reachable
#   - HAFBE schema FRESHLY installed (scripts/install_app.sh has been run
#     and the mock range has NOT been processed before).
#     To re-run mocks: ./scripts/uninstall_app.sh && ./scripts/install_app.sh
#     first. Same constraint as btracker's mock framework — see README.
#   - Accounts referenced in fixtures exist (blocktrades, gtg, steem, dan,
#     initminer); these are stock accounts on every real HAF DB.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

POSTGRES_ACCESS="${POSTGRES_URL:-postgresql://$POSTGRES_USER@$POSTGRES_HOST:$POSTGRES_PORT/haf_block_log?application_name=hafbe_mocks}"

run_psql() { psql "$POSTGRES_ACCESS" -v ON_ERROR_STOP=on "$@"; }

echo "=============================================="
echo "HAFBE proposal mock data install"
echo "  Host: $POSTGRES_HOST:$POSTGRES_PORT  User: $POSTGRES_USER"
echo "=============================================="

echo "Step 1: Installing mock SQL helpers..."
run_psql -f "$SCRIPT_DIR/sql/types.sql"
run_psql -f "$SCRIPT_DIR/sql/insert_blocks.sql"
run_psql -f "$SCRIPT_DIR/sql/insert_operations.sql"
run_psql -f "$SCRIPT_DIR/sql/update_haf_state.sql"

echo "Step 2: Inserting mock block headers..."
BLOCKS_DATA=$(cat "$SCRIPT_DIR/fixtures/blocks/data.json")
run_psql -c "SELECT hafbe_backend.insert_mock_blocks('$BLOCKS_DATA')"

echo "Step 3: Inserting mock proposal operations..."
PROPOSALS_DATA=$(cat "$SCRIPT_DIR/fixtures/proposals/data.json")
run_psql -c "SELECT hafbe_backend.insert_mock_operations('$PROPOSALS_DATA')"

echo "Step 4: Rewinding hafbe_app + hafbe_bal contexts to (mock_start - 1)"
echo "        so the mock range is the next processable batch..."
BLOCK_RANGE=$(run_psql -t -A -c "SELECT start_block || ',' || end_block FROM hafbe_backend.update_irreversible_block()")
START_BLOCK="${BLOCK_RANGE%,*}"
END_BLOCK="${BLOCK_RANGE#*,}"
echo "  Block range: $START_BLOCK..$END_BLOCK"

echo
echo "=============================================="
echo "SUCCESS: Mock data installed"
echo "=============================================="
echo "  Block range: $START_BLOCK..$END_BLOCK"
echo
echo "Next steps:"
echo "  1. Process the mock range:"
echo "       ./scripts/process_blocks.sh --stop-at-block=$END_BLOCK"
echo "  2. Verify expected state:"
echo "       ./scripts/verify_mock_data.sh"
echo
