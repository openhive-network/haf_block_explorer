#!/usr/bin/env bash
# =============================================================================
# HAFBE SQL Integration Checks
# =============================================================================
#
# A purpose-built DB integration-test suite, kept deliberately separate from the
# API tests. tests/mocks/README.md draws the line:
#
#   "Assertions then run through the REST API via the Tavern pattern suite
#    (tests/tavern/patterns-mock). If you need to guard physical table layout,
#    cache membership, or ledger row counts, add a purpose-built DB
#    integration-test suite rather than mixing SQL assertions in with the API
#    tests."
#
# This is that suite. It exists for contracts that the Tavern suites structurally
# CANNOT reach:
#
#   verify_stats_window.sql
#     hafbe_backend.aggregation_default_from() -- the 1-year default window on
#     /operation-type-statistics (issue #139). The mainnet pattern dataset spans
#     ~175 days, less than the window, so the clamp never fires there: inverting
#     its arming condition produces byte-identical fixtures. The mock dataset DOES
#     span it (block 91000006 is dated 2025-06-01 against a 2016-03-24 genesis),
#     but asserting it through the REST API would mean committing a ~40 kB /
#     366-row fixture -- 32x the largest file in patterns-mock, and brittle, since
#     every row carries a last_block_num resolved by a LATERAL block lookup.
#     The function is pure, so it is asserted directly instead.
#
# Each .sql file prints a PASS/FAIL table and RAISEs on any failure; with
# `psql -v ON_ERROR_STOP=on` that propagates a non-zero exit so CI fails the job.
#
# Requires only that HAFBE is installed. No fixture data, no processed blocks,
# no cache state -- so it can run against any database the installer has touched.
#
# Usage:
#   ./run_sql_checks.sh [OPTIONS]
#
# Options:
#   --host=HOSTNAME    PostgreSQL hostname  (default: localhost)
#   --port=PORT        PostgreSQL port      (default: 5432)
#   --user=USERNAME    PostgreSQL user      (default: haf_admin)
#   --url=URL          Full PostgreSQL URL  (overrides above)
#   --help, -h         This help
# =============================================================================

set -euo pipefail

SCRIPTDIR="$( cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 ; pwd -P )"

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

POSTGRES_ACCESS="${POSTGRES_URL:-postgresql://$POSTGRES_USER@$POSTGRES_HOST:$POSTGRES_PORT/haf_block_log?application_name=hafbe_sql_checks}"

run_psql() { psql "$POSTGRES_ACCESS" -v ON_ERROR_STOP=on "$@"; }

echo "=============================================="
echo "HAFBE SQL integration checks"
echo "  Host: $POSTGRES_HOST:$POSTGRES_PORT  User: $POSTGRES_USER"
echo "=============================================="

shopt -s nullglob
checks=("$SCRIPTDIR"/sql/*.sql)
shopt -u nullglob

if [ ${#checks[@]} -eq 0 ]; then
  echo "ERROR: no check files found in $SCRIPTDIR/sql" >&2
  exit 1
fi

for check in "${checks[@]}"; do
  echo
  echo "Running $(basename "$check")..."
  run_psql -f "$check"
done

echo
echo "All SQL integration checks passed."
