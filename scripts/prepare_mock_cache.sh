#!/usr/bin/env bash
# =============================================================================
# HAFBE Proposal Mock Cache Preparation
# =============================================================================
#
# Run AFTER:
#   1. ./tests/mocks/install_mock_data.sh   (loads fixtures + rewinds contexts)
#   2. ./scripts/process_blocks.sh ...      (processes the mock range)
#
# This is a SETUP step, not a test. It puts the mock DB into a deterministic
# state so the Tavern pattern suite (tests/tavern/patterns-mock) can assert
# stable values:
#
#   1. Refreshes the two LIVE-mode caches (witness_votes_cache and
#      proposal_vote_stats_cache). They normally refresh per-block while LIVE,
#      but if processing stopped mid-batch we force a refresh here.
#   2. Seeds a deterministic VESTS amount for `initminer` so that assertions
#      depending on its stake (e.g. proposal total_votes, and the
#      get_proposal_votes_history cache-hit pattern) do not depend on the
#      account's real, cache-version-dependent mainnet balance.
#
# Assertions about the resulting behaviour live in the Tavern pattern tests
# (tests/tavern/patterns-mock), driven through the public REST interface — not
# in a SQL verifier alongside them.
#
# Usage:
#   ./prepare_mock_cache.sh [OPTIONS]
#
# Options:
#   --host=HOSTNAME    PostgreSQL hostname  (default: localhost)
#   --port=PORT        PostgreSQL port      (default: 5432)
#   --user=USERNAME    PostgreSQL user      (default: haf_admin)
#   --url=URL          Full PostgreSQL URL  (overrides above)
#   --help, -h         This help
# =============================================================================

set -euo pipefail

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

POSTGRES_ACCESS="${POSTGRES_URL:-postgresql://$POSTGRES_USER@$POSTGRES_HOST:$POSTGRES_PORT/haf_block_log?application_name=hafbe_mock_prepare}"
BTRACKER_SCHEMA="${BTRACKER_SCHEMA:-hafbe_bal}"

# btracker_backend.nai_vests() references `asset_table` unqualified — that
# table lives in the btracker schema. Mirrors scripts/install_app.sh.
export PGOPTIONS="-c search_path=${BTRACKER_SCHEMA},public"

run_psql() { psql "$POSTGRES_ACCESS" -v ON_ERROR_STOP=on "$@"; }

echo "=============================================="
echo "HAFBE proposal mock cache preparation"
echo "  Host: $POSTGRES_HOST:$POSTGRES_PORT  User: $POSTGRES_USER"
echo "=============================================="

echo "Step 1: Refreshing vote caches (witness first, then proposal)..."
run_psql -c "SELECT hafbe_app.process_witness_votes_cache()"

# Seed a deterministic vest amount for initminer so that stake-dependent
# pattern assertions are independent of the real mainnet btracker balance
# (which varies with the underlying HAF sync cache). Runs AFTER
# process_witness_votes_cache() (which rebuilds account_vest_stats_cache from
# btracker) so this value survives into process_proposal_vote_stats_cache().
run_psql -c "
  INSERT INTO hafbe_app.account_vest_stats_cache (account_id, vests, account_vests, proxied_vests)
  SELECT av.id, 5000000, 5000000, 0
  FROM hive.accounts_view av
  WHERE av.name = 'initminer'
  ON CONFLICT (account_id) DO UPDATE
    SET vests         = 5000000,
        account_vests = 5000000,
        proxied_vests = 0;
"

run_psql -c "SELECT hafbe_app.process_proposal_vote_stats_cache()"

echo "Mock cache prepared. Endpoint behaviour is asserted by the Tavern suite"
echo "(tests/tavern/patterns-mock)."
