#!/usr/bin/env bash
# =============================================================================
# HAFBE witness vote caches against a full recompute, on a live node
# =============================================================================
#
# While hafbe is LIVE, process_witness_votes_cache(_block) updates the four witness
# vote caches incrementally. This checks, every --interval seconds, that the caches
# (and proposal_vote_stats_cache, which is derived from them) hold exactly what a
# full recompute gives at that moment, and prints one line per check:
#
#   <UTC time> block <n>: match
#   <UTC time> block <n>: DIFFERS account_vest_stats_cache: 2 rows, ...
#   <UTC time> block <n>: skipped (<why>)
#
# Each check is one REPEATABLE READ transaction, so the caches and the tables they are
# computed from are read at one snapshot: it copies the caches, runs
# process_witness_votes_cache() and process_proposal_vote_stats_cache() (the full
# recompute) and compares, then ROLLS BACK. The full recompute writes only the rows
# that differ, so a check that matches writes nothing and takes no row lock the block
# processor could wait on; one that differs holds its locks until its rollback, and
# lock_timeout bounds how long it waits for the processor's.
# That snapshot is not always one where the caches should equal the recompute: MASSIVE
# blocks (catch-up after a restart) move the HAF-registered tables but no cache, and a
# fork revert commits on its own, before the next LIVE block refreshes the caches. So
# the check compares only when the caches' state row names the context's current
# block, and is skipped when it does not, when the daily-change window has moved since
# that block (the first check after midnight, before the next block) or when it
# conflicts with a block commit.
#
# Usage:
#   ./compare_witness_votes_cache.sh [OPTIONS]
#
# Options:
#   --host=HOSTNAME    PostgreSQL hostname  (default: localhost)
#   --port=PORT        PostgreSQL port      (default: 5432)
#   --user=USERNAME    PostgreSQL user, a member of hafbe_owner (default: haf_admin)
#   --url=URL          Full PostgreSQL URL  (overrides above)
#   --interval=SECONDS Pause between checks (default: 300)
#   --count=N          Number of checks, 0 for no limit (default: 1)
#   --help, -h         This help
#
# When the checks end it prints matched=M skipped=S differs=D errors=E.
# Exit status: 1 when any check differed or failed with an error; otherwise 2 when
# no check matched (every one was skipped, so nothing was compared); otherwise 0.
# =============================================================================

set -euo pipefail

POSTGRES_USER="${POSTGRES_USER:-haf_admin}"
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_URL="${POSTGRES_URL:-}"
BTRACKER_SCHEMA="${BTRACKER_SCHEMA:-hafbe_bal}"
INTERVAL=300
COUNT=1

print_help() {
  sed -n '2,/^# =\+$/p' "$0" | sed 's/^# \?//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --host=*)     POSTGRES_HOST="${1#*=}" ;;
    --port=*)     POSTGRES_PORT="${1#*=}" ;;
    --user=*)     POSTGRES_USER="${1#*=}" ;;
    --url=*)      POSTGRES_URL="${1#*=}" ;;
    --interval=*) INTERVAL="${1#*=}" ;;
    --count=*)    COUNT="${1#*=}" ;;
    --help|-h)    print_help; exit 0 ;;
    *) echo "ERROR: unknown arg: $1"; exit 1 ;;
  esac
  shift
done

case "$INTERVAL$COUNT" in
  *[!0-9]*|'') echo "ERROR: --interval and --count take whole numbers"; exit 1 ;;
esac

POSTGRES_ACCESS="${POSTGRES_URL:-postgresql://$POSTGRES_USER@$POSTGRES_HOST:$POSTGRES_PORT/haf_block_log?application_name=hafbe_cache_compare}"

# btracker_backend.nai_vests() and the vest queries read the balance tracker's
# tables unqualified, as in block processing.
export PGOPTIONS="-c search_path=${BTRACKER_SCHEMA},public"

# One check; its result is the NOTICE line starting with RESULT.
check() {
  psql "$POSTGRES_ACCESS" -X -q -A -t -v ON_ERROR_STOP=on <<'SQL'
BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL ROLE hafbe_owner;
SET LOCAL lock_timeout = '2s';

CREATE TEMP TABLE live_avs ON COMMIT DROP AS TABLE hafbe_app.account_vest_stats_cache;
CREATE TEMP TABLE live_wv ON COMMIT DROP AS TABLE hafbe_app.witness_votes_cache;
CREATE TEMP TABLE live_wr ON COMMIT DROP AS TABLE hafbe_app.witness_rank_cache;
CREATE TEMP TABLE live_wc ON COMMIT DROP AS TABLE hafbe_app.witness_votes_change_cache;
CREATE TEMP TABLE live_pv ON COMMIT DROP AS TABLE hafbe_app.proposal_vote_stats_cache;

DO $$
DECLARE
  _block INT;
  _first INT;
  _current INT;
  _diff  TEXT;
BEGIN
  SELECT s.block_num, s.first_block_num INTO _block, _first FROM hafbe_app.witness_votes_cache_state s;
  IF _block IS NULL THEN
    RAISE NOTICE 'RESULT block -: skipped (no LIVE block refreshed the caches yet)';
    RETURN;
  END IF;
  _current := hive.app_get_current_block_num('hafbe_app');
  IF _block IS DISTINCT FROM _current THEN
    RAISE NOTICE 'RESULT block %: skipped (the context is at block %, the caches were not refreshed for it)', _block, _current;
    RETURN;
  END IF;
  IF _first IS DISTINCT FROM hafbe_app.witness_votes_cache_window_start() THEN
    RAISE NOTICE 'RESULT block %: skipped (the daily-change window moved since that block)', _block;
    RETURN;
  END IF;

  BEGIN
    PERFORM hafbe_app.process_witness_votes_cache();
    PERFORM hafbe_app.process_proposal_vote_stats_cache();
  EXCEPTION WHEN serialization_failure OR lock_not_available THEN
    RAISE NOTICE 'RESULT block %: skipped (conflicted with block processing: %)', _block, SQLERRM;
    RETURN;
  END;

  SELECT string_agg(format('%s: %s rows', d.cache, d.n), ', ')
  INTO _diff
  FROM (
    SELECT 'account_vest_stats_cache' AS cache, count(*) AS n
    FROM ((TABLE live_avs EXCEPT TABLE hafbe_app.account_vest_stats_cache)
          UNION ALL (TABLE hafbe_app.account_vest_stats_cache EXCEPT TABLE live_avs)) x
    UNION ALL
    SELECT 'witness_votes_cache', count(*)
    FROM ((TABLE live_wv EXCEPT TABLE hafbe_app.witness_votes_cache)
          UNION ALL (TABLE hafbe_app.witness_votes_cache EXCEPT TABLE live_wv)) x
    UNION ALL
    SELECT 'witness_rank_cache', count(*)
    FROM ((TABLE live_wr EXCEPT TABLE hafbe_app.witness_rank_cache)
          UNION ALL (TABLE hafbe_app.witness_rank_cache EXCEPT TABLE live_wr)) x
    UNION ALL
    SELECT 'witness_votes_change_cache', count(*)
    FROM ((TABLE live_wc EXCEPT TABLE hafbe_app.witness_votes_change_cache)
          UNION ALL (TABLE hafbe_app.witness_votes_change_cache EXCEPT TABLE live_wc)) x
    UNION ALL
    SELECT 'proposal_vote_stats_cache', count(*)
    FROM ((TABLE live_pv EXCEPT TABLE hafbe_app.proposal_vote_stats_cache)
          UNION ALL (TABLE hafbe_app.proposal_vote_stats_cache EXCEPT TABLE live_pv)) x
  ) d
  WHERE d.n > 0;

  IF _diff IS NULL THEN
    RAISE NOTICE 'RESULT block %: match', _block;
  ELSE
    RAISE NOTICE 'RESULT block %: DIFFERS %', _block, _diff;
  END IF;
END
$$;

ROLLBACK;
SQL
}

n=0
matched=0
skipped=0
differs=0
errors=0
while :; do
  n=$((n + 1))
  output="$(check 2>&1)" || true
  result="$(sed -n 's/^.*NOTICE:  RESULT //p' <<< "$output")"
  if [ -z "$result" ]; then
    result="error: $(tail -3 <<< "$output" | tr '\n' ' ')"
  fi
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $result"
  case "$result" in
    error:*)        errors=$((errors + 1)) ;;
    *': match')     matched=$((matched + 1)) ;;
    *': DIFFERS '*) differs=$((differs + 1)) ;;
    *': skipped '*) skipped=$((skipped + 1)) ;;
    *)              errors=$((errors + 1)) ;;
  esac
  if [ "$COUNT" -ne 0 ] && [ "$n" -ge "$COUNT" ]; then
    break
  fi
  sleep "$INTERVAL"
done

echo "matched=$matched skipped=$skipped differs=$differs errors=$errors"
if [ "$differs" -ne 0 ] || [ "$errors" -ne 0 ]; then
  exit 1
fi
if [ "$matched" -eq 0 ]; then
  echo "no comparison was made: every check skipped"
  exit 2
fi
exit 0
