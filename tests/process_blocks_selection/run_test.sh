#!/usr/bin/env bash
# =============================================================================
# HAF Block Explorer: which loop scripts/process_blocks.sh starts
# =============================================================================
#
# haf_app_driver.py is on PATH in the app image, so process_blocks.sh asks the
# HAF application registry whether the driver can run haf_block_explorer (the
# application, registered under the name it locks, whose group holds the
# hafbe_app context and the embedded balance tracker's): the driver
# exits before its first range when it cannot, and under a restart policy that
# is a container that never processes a block.
#
# Needs a database with haf_block_explorer installed. Puts stubs for
# haf_app_driver.py and run_with_reconnect.sh first on PATH and checks the
# choice in each registry state, then starts the real legacy main() loop
# through process_blocks.sh. It re-runs scripts/install_app.sh --only-hafbe
# over a row left under the old application name hafbe_app (which must fail)
# and over its own registration (which must keep it paused), and checks that a
# HAF with haf#403 refuses the haf_block_explorer lock when the entry procedure
# is gone. When --user may (haf_admin), it also hides HAF's
# lock helper and the registry table to cover a HAF older than both,
# re-running scripts/install_app.sh --only-hafbe there; a role that may
# not reports those cases as SKIP. Everything it changes in the registry is
# restored on exit; use a database nothing else is processing.
#
# EXIT CODES:
#   0 - Passed
#   1 - Failed
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$SCRIPT_DIR/../../scripts"

POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_USER="${POSTGRES_USER:-haf_admin}"
POSTGRES_DATABASE="${POSTGRES_DATABASE:-haf_block_log}"
PROCESSOR_USER="${PROCESSOR_USER:-hafbe_owner}"
BTRACKER_SCHEMA="${BTRACKER_SCHEMA:-hafbe_bal}"

print_help() {
    cat <<EOH
Usage: $0 [OPTIONS]

Checks which block-processing loop scripts/process_blocks.sh starts in each
state of the HAF application registry.

OPTIONS:
    --host=HOSTNAME           PostgreSQL hostname (default: localhost)
    --port=NUMBER             PostgreSQL port (default: 5432)
    --user=USERNAME           Role that changes the registry (default: haf_admin)
    --database=NAME           Database name (default: haf_block_log); process_blocks.sh
                              itself always connects to haf_block_log
    --processor-user=NAME     Role process_blocks.sh logs in as; it runs as hafbe_owner
                              (default: hafbe_owner)
    --btracker-schema=NAME    Embedded balance tracker schema (default: hafbe_bal)
    --help                    Show this help message
EOH
}

while [ $# -gt 0 ]; do
    case "$1" in
        --host=*) POSTGRES_HOST="${1#*=}" ;;
        --port=*) POSTGRES_PORT="${1#*=}" ;;
        --user=*) POSTGRES_USER="${1#*=}" ;;
        --database=*) POSTGRES_DATABASE="${1#*=}" ;;
        --processor-user=*) PROCESSOR_USER="${1#*=}" ;;
        --btracker-schema=*) BTRACKER_SCHEMA="${1#*=}" ;;
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

ADMIN_URL="postgresql://$POSTGRES_USER@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DATABASE"

sql() { psql "$ADMIN_URL" -X -Atq -v ON_ERROR_STOP=on -c "$1"; }

registered="$(sql "SELECT to_regclass('hafd.applications') IS NOT NULL")"
[ "$registered" = t ] || { echo "FAILED: this HAF has no application registry; the test needs one"; exit 1; }
read -r saved_contexts saved_procedure saved_paused < <(sql "SELECT contexts::text, process_procedure, paused FROM hafd.applications WHERE name = 'haf_block_explorer'" | tr '|' ' ') || true
if [ "${saved_procedure:-}" != hafbe_app.process_blocks ]; then
    echo "FAILED: haf_block_explorer is not registered with its entry procedure: install haf_block_explorer first"
    exit 1
fi
# The embedded balance tracker context is driven by hafbe's loop, so it is in hafbe's group
[ "$(sql "SELECT contexts @> ARRAY['hafbe_app', '$BTRACKER_SCHEMA'] FROM hafd.applications WHERE name = 'haf_block_explorer'")" = t ] \
    || { echo "FAILED: haf_block_explorer's registered contexts $saved_contexts lack $BTRACKER_SCHEMA"; exit 1; }
# The install registers under the lock name only: no row is left under the old name
[ "$(sql "SELECT count(*) FROM hafd.applications WHERE name = 'hafbe_app'")" = 0 ] \
    || { echo "FAILED: an application row named hafbe_app is registered next to haf_block_explorer"; exit 1; }

# Undo whatever this test changed, whatever way it ends
restore_haf() {
    sql "DO \$\$ BEGIN
           IF to_regclass('hafd.applications_hidden_by_test') IS NOT NULL THEN
             ALTER TABLE hafd.applications_hidden_by_test RENAME TO applications;
           END IF;
           IF to_regprocedure('hive.acquire_app_block_processor_locks_hidden_by_test(text[])') IS NOT NULL THEN
             ALTER FUNCTION hive.acquire_app_block_processor_locks_hidden_by_test(text[]) RENAME TO acquire_app_block_processor_locks;
           END IF;
           IF to_regprocedure('hafbe_app.process_blocks_hidden_by_test(hive.blocks_range)') IS NOT NULL THEN
             ALTER PROCEDURE hafbe_app.process_blocks_hidden_by_test(hive.blocks_range) RENAME TO process_blocks;
           END IF;
         END \$\$" \
        && sql "UPDATE hafd.applications
                SET name = 'haf_block_explorer', contexts = '$saved_contexts', process_procedure = '$saved_procedure',
                    paused = '$saved_paused'
                WHERE name IN ('haf_block_explorer', 'hafbe_app', 'other_app_by_test')"
}

work_dir="$(mktemp -d)"
trap 'restore_haf || echo "WARNING: could not restore the registry"; rm -rf "$work_dir"' EXIT
stubs="$work_dir/stubs"; no_driver="$work_dir/no_driver"
mkdir -p "$stubs" "$no_driver" "$work_dir/flaky" "$work_dir/failing" "$work_dir/real_legacy"
printf '#!/bin/bash\necho STUB-DRIVER "$@"\n' > "$stubs/haf_app_driver.py"
printf '#!/bin/bash\necho STUB-LEGACY "$@"\n' > "$stubs/run_with_reconnect.sh"
cp "$stubs/run_with_reconnect.sh" "$no_driver/"
# The image's run_with_reconnect.sh, less the reconnecting: runs the legacy loop itself
cat > "$work_dir/real_legacy/run_with_reconnect.sh" <<'EOS'
#!/bin/bash
[ "$1" = "--" ] && shift
exec "$@"
EOS
# psql that cannot connect once, then works: the probe must retry
printf '#!/bin/bash\nif [ ! -e "%s/flaky/failed" ]; then touch "%s/flaky/failed"; echo "psql: error: connection refused (test)" >&2; exit 2; fi\nexec "%s" "$@"\n' \
    "$work_dir" "$work_dir" "$(command -v psql)" > "$work_dir/flaky/psql"
# psql whose query fails on a live connection: the probe must not guess
printf '#!/bin/bash\necho "ERROR:  permission denied for table applications (test)" >&2\nexit 3\n' > "$work_dir/failing/psql"
chmod +x "$stubs"/* "$no_driver"/* "$work_dir"/flaky/psql "$work_dir"/failing/psql "$work_dir"/real_legacy/*

failures=0
fail() { echo "FAIL  $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/      /'; failures=$((failures + 1)); }

# Runs process_blocks.sh as hafbe_owner, with PATH_FIRST before the stubs: "$@" its arguments
run_process_blocks() {
    PATH="${PATH_FIRST:+$PATH_FIRST:}$stubs:$PATH" PGOPTIONS="-c role=hafbe_owner" \
    REGISTRY_PROBE_ATTEMPTS=2 REGISTRY_PROBE_RETRY_SECONDS=0 \
        timeout ${RUN_FOREGROUND:+--foreground} -k 10 "${RUN_TIMEOUT:-60}" bash "$SCRIPTS/process_blocks.sh" \
        --host="$POSTGRES_HOST" --port="$POSTGRES_PORT" --user="$PROCESSOR_USER" --btracker-schema="$BTRACKER_SCHEMA" --log-file=STDOUT "$@" 2>&1
}

# expect <case> <DRIVER|LEGACY|NONE> [pattern the output must hold] [-- process_blocks.sh args]
expect() {
    local name="$1" want="$2" must="${3:-}" out chosen status=0
    shift 3 || shift $#
    [ "${1:-}" = "--" ] && shift
    out="$(run_process_blocks "$@")" || status=$?
    chosen="$(grep -oE 'STUB-(DRIVER|LEGACY)' <<<"$out" | head -1)" || true
    chosen="${chosen#STUB-}"
    # The driver runs the application registered under the name it locks
    if [ "$chosen" = DRIVER ] && ! grep -q -- "--app=haf_block_explorer --postgres-url=.* --lock=haf_block_explorer" <<<"$out"; then
        chosen="DRIVER without --app=haf_block_explorer or --lock=haf_block_explorer"
    fi
    if [ "$chosen" = LEGACY ] && ! grep -q -- "CALL hafbe_app.main('hafbe_app', '$BTRACKER_SCHEMA'," <<<"$out"; then
        chosen="LEGACY without hafbe_app.main('hafbe_app', '$BTRACKER_SCHEMA', ...)"
    fi
    # NONE: no loop started, and the service fails with an ERROR line
    if [ -z "$chosen" ] && [ "$status" -ne 0 ] && grep -q "^ERROR:" <<<"$out"; then
        chosen=NONE
    fi
    if [ "$chosen" != "$want" ]; then
        fail "$name: expected $want, got ${chosen:-nothing} (exit $status)" "$out"
    elif [ -n "$must" ] && ! grep -qE -- "$must" <<<"$out"; then
        fail "$name: $chosen, but the output lacks /$must/" "$out"
    else
        echo "PASS  $name: $chosen"
    fi
}

# run_legacy <case> [pattern...]: process_blocks.sh's real legacy loop, CALL main(). It
# runs until stopped: SIGTERM after a while, to the script alone as docker stop sends it
# to PID 1 (--foreground: not to timeout's whole process group, psql included), must
# stop it through hafbe_app.stopProcessing() once it entered its loop. --stop-at-block
# holds it at the block it reached, so that it waits rather than processes. The output
# goes to a file: a psql left running when the script is killed must not hang the test.
run_legacy() {
    local name="$1" out status=0 pattern at
    shift
    at="$(sql "SELECT current_block_num FROM hafd.contexts WHERE name = 'hafbe_app'")"
    PATH_FIRST="$work_dir/real_legacy" RUN_TIMEOUT=20 RUN_FOREGROUND=1 \
        run_process_blocks --stop-at-block="$at" > "$work_dir/legacy.out" || status=$?
    out="$(cat "$work_dir/legacy.out")"
    sql "SELECT pg_terminate_backend(pid) FROM pg_stat_activity
         WHERE application_name = 'block_explorer_block_processing' AND pid <> pg_backend_pid()" >/dev/null
    if grep -v "canceling statement due to user request" <<<"$out" | grep -q "ERROR"; then
        fail "$name: exit $status" "$out"; return
    fi
    for pattern in "the legacy CALL main\(\) loop" "Entering application main loop" "Exiting application main loop" "$@"; do
        grep -qE -- "$pattern" <<<"$out" || { fail "$name: output lacks /$pattern/" "$out"; return; }
    done
    echo "PASS  $name"
}

# can_alter <owner of the object>: whether --user may rename it
can_alter() { [ "$(sql "SELECT pg_has_role(current_user, $1, 'USAGE')")" = t ]; }

# install_hafbe: re-runs scripts/install_app.sh --only-hafbe; sets install_out and install_status
install_hafbe() {
    if [ ! -f "$SCRIPTS/set_version_in_sql.pgsql" ]; then
        "$SCRIPTS/generate_version_sql.sh" "$SCRIPTS/.."
    fi
    install_status=0
    install_out="$("$SCRIPTS/install_app.sh" --host="$POSTGRES_HOST" --port="$POSTGRES_PORT" --user="$POSTGRES_USER" \
        --btracker-schema="$BTRACKER_SCHEMA" --only-hafbe --log-file=STDOUT 2>&1)" || install_status=$?
}

registry_row() { sql "SELECT name, contexts::text, process_procedure FROM hafd.applications WHERE contexts @> ARRAY['hafbe_app']"; }

expect "registered with its entry procedure" DRIVER
expect "--stop-at-block reaches the driver" DRIVER "--stop-at-block=5" -- --stop-at-block=5
PATH_FIRST="$work_dir/flaky" expect "database down at the first attempt" DRIVER \
    "attempt 1 of 2\): psql: error: connection refused \(test\); retrying"
PATH_FIRST="$work_dir/failing" expect "registry query fails" NONE \
    "ERROR: could not read the HAF application registry: ERROR:  permission denied"
expect "database unreachable: retries" NONE "attempt 1 of 2\): psql: error: .*; retrying" -- --port=1
expect "database unreachable: gives up" NONE "^ERROR: could not connect" -- --port=1

if ! command -v haf_app_driver.py >/dev/null 2>&1; then
    out="$(PATH="$no_driver:$PATH" PGOPTIONS="-c role=hafbe_owner" timeout 60 bash "$SCRIPTS/process_blocks.sh" \
        --host="$POSTGRES_HOST" --port="$POSTGRES_PORT" --user="$PROCESSOR_USER" --log-file=STDOUT 2>&1)" || true
    if grep -q "haf_app_driver.py not found" <<<"$out" && grep -q STUB-LEGACY <<<"$out"; then
        echo "PASS  registered, haf_app_driver.py not installed: LEGACY"
    else
        fail "registered, haf_app_driver.py not installed: expected LEGACY" "$out"
    fi
else
    echo "SKIP  registered, haf_app_driver.py not installed: a real haf_app_driver.py is on PATH"
fi

# The driver cannot run an app without its entry procedure: reinstall
sql "UPDATE hafd.applications SET process_procedure = NULL WHERE name = 'haf_block_explorer'"
expect "registered without an entry procedure" NONE "Reinstall haf_block_explorer"
restore_haf
sql "ALTER PROCEDURE hafbe_app.process_blocks(hive.blocks_range) RENAME TO process_blocks_hidden_by_test"
expect "entry procedure gone" NONE "Reinstall haf_block_explorer"
restore_haf
expect "entry procedure restored" DRIVER

# Another application owns the context and drives it: no second loop
# HAF's lock helpers (haf#403) refuse the block processor a lock whose application's
# entry procedure is gone; they find the row by the lock name, haf_block_explorer
if [ "$(sql "SELECT to_regprocedure('hive._missing_app_process_procedure(text)') IS NOT NULL")" = t ]; then
    sql "ALTER PROCEDURE hafbe_app.process_blocks(hive.blocks_range) RENAME TO process_blocks_hidden_by_test"
    out="$(sql "SELECT hive.acquire_app_block_processor_locks(ARRAY['haf_block_explorer'])" 2>&1)" && status=0 || status=$?
    restore_haf
    if [ "$status" -ne 0 ] && grep -q "lock on haf_block_explorer: .*reinstall the application" <<<"$out"; then
        echo "PASS  entry procedure gone: the haf_block_explorer lock is refused"
    else
        fail "entry procedure gone: expected the haf_block_explorer lock refused (exit $status)" "$out"
    fi
else
    echo "SKIP  entry procedure gone, lock refused: this HAF has no hive._missing_app_process_procedure (haf#403)"
fi

# A row left under the old application name by an install older than the rename: the
# processor and the install both refuse it, naming the way out, and the row stays
sql "UPDATE hafd.applications SET name = 'hafbe_app' WHERE name = 'haf_block_explorer'"
expect "registered under the old name hafbe_app" NONE "SELECT hive.app_unregister\('hafbe_app'\); and reinstall"
before="$(registry_row)"
install_hafbe
after="$(registry_row)"
if [ "$install_status" -ne 0 ] \
    && grep -q "as application hafbe_app, not haf_block_explorer. Replay haf_block_explorer from scratch, or run SELECT hive.app_unregister('hafbe_app'); and reinstall" <<<"$install_out" \
    && [ "$before" = "$after" ] && [ "$(sql "SELECT count(*) FROM hafd.applications WHERE name = 'haf_block_explorer'")" = 0 ]; then
    echo "PASS  install over the old name hafbe_app fails and leaves the row"
else
    fail "install over the old name hafbe_app: exit $install_status, row before '$before', after '$after'" \
        "$(grep -E 'ERROR|WARNING' <<<"$install_out" | head -20 || true)"
fi
restore_haf

# Reinstalling over its own registration keeps it, paused included
sql "UPDATE hafd.applications SET paused = TRUE WHERE name = 'haf_block_explorer'"
install_hafbe
row="$(sql "SELECT name, process_procedure, paused, contexts @> ARRAY['hafbe_app', '$BTRACKER_SCHEMA'] FROM hafd.applications WHERE contexts && ARRAY['hafbe_app', '$BTRACKER_SCHEMA']")"
if [ "$install_status" -eq 0 ] && [ "$row" = "haf_block_explorer|hafbe_app.process_blocks|t|t" ]; then
    echo "PASS  reinstall over haf_block_explorer keeps the registration paused"
else
    fail "reinstall over haf_block_explorer: exit $install_status, registry rows '$row'" \
        "$(grep -E 'ERROR|WARNING' <<<"$install_out" | head -20 || true)"
fi
restore_haf
expect "registered after the reinstall" DRIVER

sql "UPDATE hafd.applications SET name = 'other_app_by_test' WHERE name = 'haf_block_explorer'"
expect "context owned by another application" NONE "belongs to another application"

# A row under another name, for other contexts, does not count for haf_block_explorer
sql "UPDATE hafd.applications SET contexts = ARRAY['other_context_by_test'] WHERE name = 'other_app_by_test'"
expect "not in the registry" LEGACY "running the legacy CALL main\(\) loop"
expect "--stop-at-block reaches the legacy loop" LEGACY "main\('hafbe_app', '$BTRACKER_SCHEMA', 5\)" -- --stop-at-block=5
run_legacy "real legacy main() starts and stops"

# The cases below hide parts of HAF to cover a HAF older than them
lock_owner="(SELECT proowner FROM pg_proc WHERE oid = 'hive.acquire_app_block_processor_locks(text[])'::regprocedure)"
registry_owner="(SELECT relowner FROM pg_class WHERE oid = 'hafd.applications'::regclass)"
if can_alter "$lock_owner"; then
    sql "ALTER FUNCTION hive.acquire_app_block_processor_locks(text[]) RENAME TO acquire_app_block_processor_locks_hidden_by_test"
    run_legacy "real legacy main() on a HAF without the lock helpers" "without the haf_block_explorer application lock"
else
    echo "SKIP  HAF without the lock helpers: $POSTGRES_USER may not rename hive.acquire_app_block_processor_locks"
fi
restore_haf
expect "registry restored" DRIVER

# Hiding the registry table hides it from HAF's own functions too, so the legacy loop
# itself is not started on it
if can_alter "$registry_owner"; then
    sql "ALTER TABLE hafd.applications RENAME TO applications_hidden_by_test"
    install_hafbe
    if [ "$install_status" -eq 0 ] && grep -q "This HAF has no application registry" <<<"$install_out"; then
        echo "PASS  install on a HAF without the registry"
    else
        fail "install on a HAF without the registry: exit $install_status" "$(grep -E 'ERROR|WARNING' <<<"$install_out" | head -20 || true)"
    fi
    expect "HAF without the registry" LEGACY "running the legacy CALL main\(\) loop"
    restore_haf
    expect "registry restored after the install" DRIVER
else
    echo "SKIP  HAF without the registry: $POSTGRES_USER may not rename hafd.applications"
fi

if [ "$failures" -ne 0 ]; then
    echo "FAILED: $failures case(s)"
    exit 1
fi
echo "PASSED"
