#!/usr/bin/env bash
# The step functions are called indirectly, through `step`.
# shellcheck disable=SC2317,SC2329
# The checks AIDEV's verification slots run (.aidev/project.yaml), as one junit
# report per suite: each named step is a test case, its log the failure body.
#
#   .aidev/run-checks.sh <suite> <step>...
#
#   - shellcheck      ShellCheck on every *.sh outside submodules/ (CI's
#                     lint_bash_scripts fails on error severity only; the tree is clean
#                     at the default severity, so this holds it there)
#   - sqlfluff        sqlfluff 2.1.4 with .sqlfluff (CI's lint_sql_scripts) on the tree;
#                     fails on a violation in a file not listed in
#                     .aidev/sqlfluff-baseline (the files that had violations when
#                     AIDEV was onboarded), and reports those files' violations
#   - sql-registered  every .sql file under db/, backend/ and endpoints/ is applied by
#                     scripts/install_app.sh, except those .aidev/sql-unregistered lists
#   - install         a copy-on-write clone of the shared 5M-block HAF for this run
#                     (haf_shared.clone_run_database on AIDEV_EXTERNAL_HAF_HOST:_PORT, as
#                     haf_shared_consumer); HAfAH into it from the runtime image's
#                     /opt/hafah (what CI's compose installs from its HAfAH image), then
#                     scripts/install_app.sh: balance tracker (schema hafbe_bal) and
#                     reputation tracker from submodules/, then haf_block_explorer
#   - reinstall       what CI's setup-scripts-test does: install_app.sh over the installed
#                     apps, scripts/uninstall_app.sh, then install_app.sh again
#   - sync            the block processors of haf_block_explorer (with balance tracker) and
#                     reputation tracker to block 5000000 in the clone, then what CI's
#                     sync job and wait-for-haf-be-startup.sh do after it: the witness
#                     votes cache, hafbe's indexes and the HAF indexes it registered
#   - regression      tests/regression against the synced clone (.aidev/hafbe_regression.py)
#   - tavern          tests/tavern/patterns-mainnet against PostgREST over the synced clone
#                     (.aidev/hafbe_tavern.py); one junit case per test
#
# install, reinstall, sync, regression and tavern need the shared HAF (sandbox.external
# haf, provider haf/haf); the clone is dropped when the script exits, pass or fail.
# Reports go to test-results/<suite>/: junit.xml (one case per step) plus regression.xml
# and tavern.xml.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

suite="${1:?usage: $0 <suite> <step>...}"; shift
out="test-results/$suite"
rm -rf "$out"; mkdir -p "$out"
cases="$out/cases.tsv"; : > "$cases"

# The block the shared HAF is replayed to, and CI's --stop-at-block.
SYNC_TARGET=5000000
SYNC_TIMEOUT_S="${HAFBE_SYNC_TIMEOUT_S:-1800}"

# The shared HAF trusts haf_shared_consumer from the fleet LAN: no password.
CONSUMER_URL="postgresql://haf_shared_consumer@${AIDEV_EXTERNAL_HAF_HOST:-}:${AIDEV_EXTERNAL_HAF_PORT:-5432}"
clone=""; clone_id=""
# The script's own stderr, which a step's redirected output does not reach: where
# the clone's name and its drop are reported.
exec 3>&2

status=0
# record CASES_FILE NAME RC SECONDS LOG
record() {
    if [ "$3" -eq 0 ]; then
        printf 'case\t%s\tpass\t%s\t\n' "$2" "$4" >> "$1"
    else
        printf 'case\t%s\tfail\t%s\texit %s\t%s\n' "$2" "$4" "$3" "$5" >> "$1"
    fi
}

step() {
    local name="$1"; shift
    local log="$out/$name.log" t0=$SECONDS rc=0
    echo "== $name" >&2
    "$@" > "$log" 2>&1 < /dev/null || rc=$?
    [ "$rc" -eq 0 ] || { status=1; tail -40 "$log" >&2; }
    record "$cases" "$name" "$rc" "$((SECONDS - t0))" "$log"
}

shell_scripts() {
    find . -path ./.git -prune -o -path ./submodules -prune -o -path ./test-results -prune \
        -o -name '*.sh' -type f -print | sort
}

run_shellcheck() {
    shellcheck --version | head -2
    shell_scripts | xargs shellcheck -f gcc
}

run_sqlfluff() {
    sqlfluff --version
    local report="$out/sqlfluff.txt" file count new=0
    # sqlfluff exits 1 on any violation; the verdict is the baseline comparison below.
    sqlfluff lint --dialect postgres --format github-annotation-native . > "$report" 2>&1
    while read -r count file; do
        if grep -qxF "$file" .aidev/sqlfluff-baseline; then
            echo "known (in .aidev/sqlfluff-baseline): $file: $count violation(s)"
        else
            echo "NEW: $file: $count violation(s)"
            grep -F "file=$file," "$report"
            new=1
        fi
    done < <(grep -o 'file=[^,]*' "$report" | sed 's/^file=//' | sort | uniq -c)
    if grep -q 'Traceback' "$report"; then
        cat "$report"; return 1
    fi
    [ "$new" -eq 0 ] && echo "no sqlfluff violation outside the baseline files"
    return "$new"
}

sql_registered() {
    local f missing=0
    while IFS= read -r f; do
        if grep -qxF "$f" .aidev/sql-unregistered; then
            echo "not applied, deliberately (.aidev/sql-unregistered): $f"
        elif ! grep -qF "\$HAFBE_DIR/$f\"" scripts/install_app.sh; then
            echo "not applied by scripts/install_app.sh: $f"
            missing=1
        fi
    done < <(find db backend endpoints -name '*.sql' | sort)
    [ "$missing" -eq 0 ] && echo "every other .sql file under db/, backend/ and endpoints/ is applied"
    return "$missing"
}

# The install scripts write their logs and version files next to themselves and read
# the version from git, which a workflow checkout may not have: stage the sources (the
# app's and both submodules') in a scratch directory and write the versions there. The
# shared HAF provides the six app roles and the consumer may neither create nor drop
# roles, so the staged db/builtin_roles.sql files are empty and the staged uninstall
# drops the schemas only (DROP OWNED BY would revoke the roles' grants on every other
# run's clone too: database privileges are cluster-wide). install_app.sh and
# uninstall_app.sh name database haf_block_log; the staged copies name the clone.
stage=""
stage_sources() {
    [ -n "$stage" ] && return 0
    local d m hash
    for m in btracker reptracker; do
        if [ ! -f "submodules/$m/scripts/install_app.sh" ]; then
            echo "submodules/$m is not checked out: the install steps need both submodules"
            return 1
        fi
    done
    stage="$(mktemp -d)"
    mkdir -p "$stage/submodules"
    cp -r db backend endpoints scripts "$stage/"
    cp -r submodules/btracker submodules/reptracker "$stage/submodules/"
    for d in "$stage" "$stage/submodules/btracker" "$stage/submodules/reptracker"; do
        echo "-- the app's roles are provided by the shared HAF" > "$d/db/builtin_roles.sql"
        printf '#!/bin/sh\n# versions are written by .aidev/run-checks.sh\n' > "$d/scripts/generate_version_sql.sh"
    done
    hash="$(git rev-parse HEAD 2>/dev/null || echo aidev)"
    echo "TRUNCATE TABLE hafbe_app.version; INSERT INTO hafbe_app.version(git_hash) VALUES ('$hash');" \
        > "$stage/scripts/set_version_in_sql.pgsql"
    for m in btracker reptracker; do
        hash="$(git -C "submodules/$m" rev-parse HEAD 2>/dev/null || echo aidev)"
        echo "TRUNCATE TABLE version; INSERT INTO version(git_hash) VALUES ('$hash');" \
            > "$stage/submodules/$m/scripts/set_version_in_sql.pgsql"
    done
    sed -i "s#/haf_block_log?#/$clone?#" "$stage/scripts/install_app.sh" "$stage/scripts/uninstall_app.sh"
    sed -i '/DROP OWNED\|DROP ROLE/d' "$stage/scripts/uninstall_app.sh"
    # HAfAH, which CI's compose installs from its image before haf_block_explorer
    # (hafbe's SQL calls hafah_backend): the runtime image carries that image's sources.
    if [ ! -f /opt/hafah/scripts/install_app.sh ]; then
        echo "/opt/hafah is missing: the runtime image carries HAfAH's sources (.aidev/runtime/Dockerfile)"
        return 1
    fi
    cp -r /opt/hafah "$stage/hafah"
    echo "-- hafah_owner and hafah_user are provided by the shared HAF" > "$stage/hafah/db/builtin_roles.sql"
}

# This run's own clone of the shared HAF, named after the suite, the time and a
# random suffix so concurrent runs never share one.
open_clone() {
    [ -n "$clone" ] && return 0
    if [ -z "${AIDEV_EXTERNAL_HAF_HOST:-}" ]; then
        echo "AIDEV_EXTERNAL_HAF_HOST is unset: this slot needs sandbox.external haf (provider haf/haf)"
        return 1
    fi
    local run_id
    run_id="hafbe-$suite-$(date -u +%Y%m%d%H%M%S)-$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
    clone="$(psql "$CONSUMER_URL/haf_shared" -v ON_ERROR_STOP=on -Atc "select haf_shared.clone_run_database('$run_id')")" || return 1
    clone_id="$run_id"
    export HAFBE_TEST_DB_URL="$CONSUMER_URL/$clone"
    echo "== shared HAF clone $clone ($CONSUMER_URL)" | tee /dev/fd/3
    # The consumer owns the clone; the apps' roles need to create their schemas in it.
    psql "$HAFBE_TEST_DB_URL" -v ON_ERROR_STOP=on -c "GRANT CREATE, CONNECT ON DATABASE \"$clone\" TO hafbe_owner, hafbe_user, btracker_owner, btracker_user, reptracker_owner, reptracker_user, hafah_owner, hafah_user"
}

drop_clone() {
    [ -n "$clone" ] || return 0
    if psql "$CONSUMER_URL/haf_shared" -v ON_ERROR_STOP=on -qAtc "select haf_shared.drop_run_database('$clone_id')"; then
        echo "== dropped shared HAF clone $clone" >&3
    else
        echo "== could not drop shared HAF clone $clone; the provider reaps it after its TTL" >&3
    fi
}

sync_pids=()
cleanup() {
    local pid
    for pid in "${sync_pids[@]}"; do kill "$pid" 2>/dev/null; done
    drop_clone
    if [ -n "$stage" ]; then rm -rf "$stage"; fi
}
trap cleanup EXIT

# With the block search indexes, as CI's compose installs it (backend-setup:
# --blocksearch-indexes=true); get_block_by_op refuses without them.
app_install() {
    (cd "$stage" && bash scripts/install_app.sh --host="$AIDEV_EXTERNAL_HAF_HOST" \
        --port="${AIDEV_EXTERNAL_HAF_PORT:-5432}" --user=haf_shared_consumer --log-file=STDOUT \
        --blocksearch-indexes=true) || return 1
    psql "$HAFBE_TEST_DB_URL" -v ON_ERROR_STOP=on -Atc "select git_hash from hafbe_app.version"
}

install() {
    open_clone && stage_sources || return 1
    echo "== HAfAH $(grep -o "'[0-9a-f]*'" "$stage/hafah/scripts/set_version_in_sql.pgsql")"
    (cd "$stage/hafah" && bash scripts/install_app.sh --postgres-url="$HAFBE_TEST_DB_URL") || return 1
    echo "== haf_block_explorer"
    app_install
}

reinstall() {
    open_clone && stage_sources || return 1
    echo "== install over the installed apps"
    app_install || return 1
    echo "== uninstall"
    (cd "$stage" && bash scripts/uninstall_app.sh --host="$AIDEV_EXTERNAL_HAF_HOST" \
        --port="${AIDEV_EXTERNAL_HAF_PORT:-5432}" --user=haf_shared_consumer --log-file=STDOUT) || return 1
    if [ "$(psql "$HAFBE_TEST_DB_URL" -Atc "select count(*) from pg_namespace where nspname in ('hafbe_app', 'hafbe_backend', 'hafbe_endpoints')")" != 0 ]; then
        echo "uninstall_app.sh left hafbe schemas behind"; return 1
    fi
    echo "== install again"
    app_install
}

# Run "$@" against the clone; the steps after install need it to have made one.
on_clone() {
    if [ -z "$clone" ]; then
        echo "no shared HAF clone: install did not run or could not create one"
        return 1
    fi
    "$@"
}

context_blocks() {
    psql "$HAFBE_TEST_DB_URL" -Atc "select coalesce(min(current_block_num), 0) from hafd.contexts where name in ($1)"
}

# The block processors as scripts/process_blocks.sh and the reptracker's run them
# without haf_app_driver.py (the legacy CALL main() loop), each as its owner role.
# hafbe's main() does not return at its limit (it waits for the next block), so it is
# stopped with hafbe_app.stopProcessing() once both of its contexts reach the target.
sync_apps() {
    local head t0=$SECONDS rep hafbe
    head="$(psql "$HAFBE_TEST_DB_URL" -Atc "select hive.app_get_irreversible_block()")" || return 1
    echo "shared HAF irreversible head: $head, target: $SYNC_TARGET"
    [ "$head" -ge "$SYNC_TARGET" ] || { echo "the shared HAF is not replayed to $SYNC_TARGET"; return 1; }
    # statement_timeout bounds each processor on the server too: a run killed from
    # outside (a gate's wall) cannot stop them, and they would go on syncing a clone
    # nobody reads until the provider reaps it.
    psql "$HAFBE_TEST_DB_URL?application_name=reptracker_block_processing" -v ON_ERROR_STOP=on \
        -c "SET statement_timeout = '${SYNC_TIMEOUT_S}s'" -c "SET ROLE reptracker_owner" -c "SET SEARCH_PATH TO reptracker_app" \
        -c "CALL reptracker_app.main('reptracker_app', $SYNC_TARGET)" > "$out/sync-reptracker.log" 2>&1 &
    rep=$!; sync_pids+=("$rep")
    psql "$HAFBE_TEST_DB_URL?application_name=block_explorer_block_processing" -v ON_ERROR_STOP=on \
        -c "SET statement_timeout = '${SYNC_TIMEOUT_S}s'" -c "SET ROLE hafbe_owner" -c "SET temp_buffers = '16MB'" -c "SET SEARCH_PATH TO hafbe_bal" \
        -c "CALL hafbe_app.main('hafbe_app', 'hafbe_bal', $SYNC_TARGET)" > "$out/sync-hafbe.log" 2>&1 &
    hafbe=$!; sync_pids+=("$hafbe")
    while [ "$(context_blocks "'hafbe_app', 'hafbe_bal'")" -lt "$SYNC_TARGET" ]; do
        if ! kill -0 "$hafbe" 2>/dev/null; then
            echo "hafbe block processing exited before block $SYNC_TARGET:"; tail -30 "$out/sync-hafbe.log"; return 1
        fi
        if [ $((SECONDS - t0)) -ge "$SYNC_TIMEOUT_S" ]; then
            echo "hafbe not at block $SYNC_TARGET after ${SYNC_TIMEOUT_S}s"; return 1
        fi
        sleep 10
    done
    echo "hafbe_app and hafbe_bal at $SYNC_TARGET after $((SECONDS - t0))s; stopping hafbe"
    psql "$HAFBE_TEST_DB_URL" -v ON_ERROR_STOP=on -c "SET ROLE hafbe_owner" -c "SELECT hafbe_app.stopProcessing()" || return 1
    wait "$hafbe" || { echo "hafbe block processing failed:"; tail -30 "$out/sync-hafbe.log"; return 1; }
    while kill -0 "$rep" 2>/dev/null && [ $((SECONDS - t0)) -lt "$SYNC_TIMEOUT_S" ]; do sleep 5; done
    wait "$rep" || { echo "reptracker block processing failed:"; tail -30 "$out/sync-reptracker.log"; return 1; }
    [ "$(context_blocks "'reptracker_app'")" -ge "$SYNC_TARGET" ] || { echo "reptracker_app short of $SYNC_TARGET"; return 1; }
    echo "synced in $((SECONDS - t0))s"
    # What CI's sync job runs after the processors, then wait-for-haf-be-startup.sh's
    # index steps (hived, which builds registered indexes in production, is not running).
    psql "$HAFBE_TEST_DB_URL" -v ON_ERROR_STOP=on -c "SET ROLE hafbe_owner" \
        -c "SET search_path TO hafbe_bal, reptracker_app" -c "SELECT hafbe_app.process_witness_votes_cache()" \
        -c "SELECT hafbe_app.create_hafbe_indexes()" -c "RESET ROLE" \
        -c "SELECT hive.app_restore_indexes('hafbe_app')" || return 1
    [ "$(psql "$HAFBE_TEST_DB_URL" -Atc "select hive.check_if_registered_indexes_created('hafbe_app')")" = t ] \
        || { echo "hafbe's registered HAF indexes are not created"; return 1; }
    psql "$HAFBE_TEST_DB_URL" -c "select name, current_block_num from hafd.contexts order by name"
    echo "sync complete in $((SECONDS - t0))s"
}

for s in "$@"; do
    case "$s" in
        shellcheck) step shellcheck run_shellcheck ;;
        sqlfluff) step sqlfluff run_sqlfluff ;;
        sql-registered) step sql-registered sql_registered ;;
        install) step install install ;;
        reinstall) step reinstall reinstall ;;
        sync) step sync on_clone sync_apps ;;
        regression) step regression on_clone python3 .aidev/hafbe_regression.py "$out" ;;
        tavern) step tavern on_clone python3 .aidev/hafbe_tavern.py "$out" ;;
        *) echo "unknown step: $s" >&2; exit 2 ;;
    esac
done
python3 .aidev/junit_cases.py "$out/junit.xml" "$suite" "$cases"
exit "$status"
