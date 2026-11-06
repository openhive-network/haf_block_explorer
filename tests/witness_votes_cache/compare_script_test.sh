#!/usr/bin/env bash
# =============================================================================
# HAF Block Explorer: scripts/compare_witness_votes_cache.sh
# =============================================================================
#
# Runs the live shadow comparison against a database with hafbe synced and its
# witness vote caches filled, in three states it commits and then undoes:
#   - the state row names the context's current block: the script must report
#     match and exit 0;
#   - the same, with one witness_votes_cache row altered: DIFFERS and exit 1;
#   - the state row one block behind the context's current block (a MASSIVE
#     catch-up), and one block ahead of it (a fork reverted the context): every one
#     of three checks skipped, so nothing was compared, and exit 2.
# On exit it recomputes the caches in full and puts the state row back as it was.
# The connecting role must be a member of hafbe_owner, as for the script.
#
# Usage: compare_script_test.sh --url=URL [--btracker-schema=NAME]
#
# EXIT CODES:
#   0 - Passed
#   1 - Failed
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPARE="$SCRIPT_DIR/../../scripts/compare_witness_votes_cache.sh"

POSTGRES_URL=""
BTRACKER_SCHEMA="${BTRACKER_SCHEMA:-hafbe_bal}"

while [ $# -gt 0 ]; do
    case "$1" in
        --url=*)             POSTGRES_URL="${1#*=}" ;;
        --btracker-schema=*) BTRACKER_SCHEMA="${1#*=}" ;;
        *) echo "ERROR: Unknown option: $1"; exit 1 ;;
    esac
    shift
done
[ -n "$POSTGRES_URL" ] || { echo "ERROR: --url is required"; exit 1; }

sql() {
    PGOPTIONS="-c search_path=${BTRACKER_SCHEMA},public" \
        psql "$POSTGRES_URL" -X -q -A -t -v ON_ERROR_STOP=on -c "$1"
}

saved="$(sql "SELECT format('%s,%s', block_num, coalesce(first_block_num::TEXT, 'NULL')) FROM hafbe_app.witness_votes_cache_state")"

restore() {
    sql "SET ROLE hafbe_owner;
         SELECT hafbe_app.process_witness_votes_cache();
         SELECT hafbe_app.process_proposal_vote_stats_cache();
         DELETE FROM hafbe_app.witness_votes_cache_state;" > /dev/null
    if [ -n "$saved" ]; then
        sql "SET ROLE hafbe_owner;
             INSERT INTO hafbe_app.witness_votes_cache_state (singleton, block_num, first_block_num)
             VALUES (TRUE, ${saved});" > /dev/null
    fi
}
trap restore EXIT

# set_state OFFSET: the state row names the context's current block + OFFSET.
set_state() {
    sql "SET ROLE hafbe_owner;
         INSERT INTO hafbe_app.witness_votes_cache_state (singleton, block_num, first_block_num)
         VALUES (TRUE, hive.app_get_current_block_num('hafbe_app') + $1, hafbe_app.witness_votes_cache_window_start())
         ON CONFLICT (singleton) DO UPDATE SET
           block_num = EXCLUDED.block_num, first_block_num = EXCLUDED.first_block_num;" > /dev/null
}

failed=0
# expect CASE EXIT_STATUS PATTERNS [SCRIPT_ARGS...]: SCRIPT_ARGS default to --count=1;
# PATTERNS holds one grep -E pattern per line, each of which the output must contain.
expect() {
    local rc=0 output pattern ok=1 case="$1" status="$2" patterns="$3"
    shift 3
    [ $# -gt 0 ] || set -- --count=1
    output="$(BTRACKER_SCHEMA="$BTRACKER_SCHEMA" "$COMPARE" --url="$POSTGRES_URL" "$@" 2>&1)" || rc=$?
    [ "$rc" -eq "$status" ] || ok=0
    while IFS= read -r pattern; do
        grep -q -E -- "$pattern" <<< "$output" || ok=0
    done <<< "$patterns"
    if [ "$ok" -eq 1 ]; then
        echo "PASS $case: exit $rc, $output"
    else
        echo "FAIL $case: expected exit $status and '$patterns', got exit $rc: $output"
        failed=1
    fi
}

# The caches as the sync left them, so the full recompute matches them.
sql "SET ROLE hafbe_owner;
     SELECT hafbe_app.process_witness_votes_cache();
     SELECT hafbe_app.process_proposal_vote_stats_cache();" > /dev/null

set_state 0
expect "state at the current block" 0 ': match$
^matched=1 skipped=0 differs=0 errors=0$'

sql "SET ROLE hafbe_owner;
     UPDATE hafbe_app.witness_votes_cache SET votes = votes + 1
     WHERE witness_id = (SELECT min(witness_id) FROM hafbe_app.witness_votes_cache);" > /dev/null
expect "state at the current block, a cache row altered" 1 ': DIFFERS witness_votes_cache: 2 rows$
^matched=0 skipped=0 differs=1 errors=0$'

set_state -1
expect "state behind the current block, a cache row altered" 2 ': skipped \(the context is at block [0-9]+, the caches were not refreshed for it\)$
^matched=0 skipped=3 differs=0 errors=0$
^no comparison was made: every check skipped$' --count=3 --interval=0

set_state 1
expect "state ahead of the current block, a cache row altered" 2 ': skipped \(the context is at block [0-9]+, the caches were not refreshed for it\)$
^matched=0 skipped=3 differs=0 errors=0$
^no comparison was made: every check skipped$' --count=3 --interval=0

[ "$failed" -eq 0 ]
