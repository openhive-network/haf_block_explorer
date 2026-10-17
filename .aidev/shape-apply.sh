#!/usr/bin/env bash
# performance.shape.apply (.aidev/project.yaml): installs this tree's database code
# (haf_block_explorer, and the balance tracker and reputation tracker submodules it
# installs into hafbe_bal and reptracker_app) on a copy of the db-shape, the way
# scripts/install_app.sh installs it.
#
#   AIDEV_DB_SHAPE_PSQL=<psql invocation reading SQL on stdin> .aidev/shape-apply.sh
#
# The shape server has no network, so install_app.sh cannot be given a DSN: it runs
# unchanged from a scratch copy of the sources with .aidev/shape-psql.sh first on
# PATH as `psql`, which feeds each of its psql calls to $AIDEV_DB_SHAPE_PSQL on
# stdin. The files, their order and the statements between them are install_app.sh's
# own, with these stubs in the copy:
#   - db/builtin_roles.sql (all three apps) is empty, as in .aidev/run-checks.sh: the
#     shape restores the source's roles;
#   - db/hafbe_app.sql, the balance tracker's db/btracker_app.sql and the reputation
#     tracker's db/reptracker_app.sql are empty: they create each app's HAF context,
#     its tables and its block-processing procedures, and decide that from
#     hafd.contexts, which a shape restores without rows. The shape already carries
#     the source's tables with their statistics, which are what the plans need, and
#     no API statement calls the processing procedures. The copy of db/hafbe_app.sql
#     keeps the CREATE TABLE of a table added since the shape was captured
#     (hafbe_app.wallet_stats_by_day), empty and without statistics;
#   - the version files are written here (a workflow checkout may have no git
#     metadata for the submodules), as in .aidev/run-checks.sh.
# Everything else (types, views, backend and endpoint functions, grants) installs
# as install_app.sh installs it.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${AIDEV_DB_SHAPE_PSQL:?set by aidev db shape: the psql invocation reaching the shape copy}"
: "${AIDEV_DB_SHAPE_DATABASE:?set by aidev db shape: the shape copy psql reaches}"

for m in btracker reptracker; do
    if [ ! -f "submodules/$m/scripts/install_app.sh" ]; then
        echo "submodules/$m is not checked out: the install needs both submodules" >&2
        exit 1
    fi
done

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/submodules"
cp -r db backend endpoints scripts "$stage/"
cp -r submodules/btracker submodules/reptracker "$stage/submodules/"
for d in "$stage" "$stage/submodules/btracker" "$stage/submodules/reptracker"; do
    echo "-- the app's roles are restored with the shape" > "$d/db/builtin_roles.sql"
    printf '#!/bin/sh\n# versions are written by .aidev/shape-apply.sh\n' > "$d/scripts/generate_version_sql.sh"
done
for f in db/hafbe_app.sql submodules/btracker/db/btracker_app.sql submodules/reptracker/db/reptracker_app.sql; do
    echo "-- the shape carries this app's tables and statistics (.aidev/shape-apply.sh)" > "$stage/$f"
done
# The balance tracker's backend/shared/nai_types.sql checks its NAI constants against
# asset_table, which btracker_app.sql seeds and the shape restores empty: keep the
# seed. (The copy's heaps are restored from the shape after the install, so the rows
# do not outlive it.)
# install_app.sh loads btracker_app.sql twice, hence ON CONFLICT.
sed -n '/INSERT INTO asset_table/,/;/p' submodules/btracker/db/btracker_app.sql \
    | sed 's/;[[:space:]]*$/ ON CONFLICT DO NOTHING;/' >> "$stage/submodules/btracker/db/btracker_app.sql"
if ! grep -q "INSERT INTO asset_table" "$stage/submodules/btracker/db/btracker_app.sql"; then
    echo "submodules/btracker/db/btracker_app.sql no longer seeds asset_table: update .aidev/shape-apply.sh" >&2
    exit 1
fi
# A table hafbe_app.sql adds after the shape was captured is not in the shape: create
# it (empty, without statistics) so the API functions that read it can run.
{
    echo "SET ROLE hafbe_owner;"
    sed -n '/CREATE TABLE hafbe_app.wallet_stats_by_day/,/);/p' db/hafbe_app.sql \
        | sed 's/CREATE TABLE /CREATE TABLE IF NOT EXISTS /'
    echo "RESET ROLE;"
} >> "$stage/db/hafbe_app.sql"
if ! grep -q "CREATE TABLE IF NOT EXISTS hafbe_app.wallet_stats_by_day" "$stage/db/hafbe_app.sql"; then
    echo "db/hafbe_app.sql no longer creates hafbe_app.wallet_stats_by_day: update .aidev/shape-apply.sh" >&2
    exit 1
fi
hash="$(git rev-parse HEAD 2>/dev/null || echo aidev)"
echo "TRUNCATE TABLE hafbe_app.version; INSERT INTO hafbe_app.version(git_hash) VALUES ('$hash');" \
    > "$stage/scripts/set_version_in_sql.pgsql"
for m in btracker reptracker; do
    hash="$(git -C "submodules/$m" rev-parse HEAD 2>/dev/null || echo aidev)"
    echo "TRUNCATE TABLE version; INSERT INTO version(git_hash) VALUES ('$hash');" \
        > "$stage/submodules/$m/scripts/set_version_in_sql.pgsql"
done
mkdir "$stage/bin"
ln -s "$PWD/.aidev/shape-psql.sh" "$stage/bin/psql"

shape_psql=()
eval "shape_psql=($AIDEV_DB_SHAPE_PSQL)"
# A shape restores every schema and object owned by postgres (pg_dump --no-owner),
# and the installers replace functions and types as each app's owner role. The
# schemas cannot be dropped as HAfAH's are (they hold the tables whose statistics the
# plans need), so give each app's schemas and objects back to the owner role they
# have in production, and let the app roles create schemas in the copy.
"${shape_psql[@]}" -v ON_ERROR_STOP=1 -v db="$AIDEV_DB_SHAPE_DATABASE" <<'SQL'
SET client_min_messages = warning;
GRANT CREATE, CONNECT ON DATABASE :"db" TO hafbe_owner, hafbe_user, btracker_owner, btracker_user, reptracker_owner, reptracker_user;
DO $$
DECLARE
  r RECORD;
  owner_of CONSTANT JSONB := '{
    "hafbe_app": "hafbe_owner", "hafbe_backend": "hafbe_owner", "hafbe_endpoints": "hafbe_owner",
    "hafbe_bal": "btracker_owner", "btracker_backend": "btracker_owner", "btracker_endpoints": "btracker_owner",
    "reptracker_app": "reptracker_owner", "reptracker_backend": "reptracker_owner", "reptracker_endpoints": "reptracker_owner"
  }';
BEGIN
  FOR r IN SELECT n.nspname, owner_of ->> n.nspname AS owner FROM pg_namespace n WHERE owner_of ? n.nspname LOOP
    EXECUTE format('ALTER SCHEMA %I OWNER TO %I', r.nspname, r.owner);
  END LOOP;
  FOR r IN
    SELECT c.oid::regclass AS obj, owner_of ->> n.nspname AS owner,
           CASE c.relkind WHEN 'v' THEN 'VIEW' WHEN 'm' THEN 'MATERIALIZED VIEW' WHEN 'S' THEN 'SEQUENCE' WHEN 'f' THEN 'FOREIGN TABLE' ELSE 'TABLE' END AS kind
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE owner_of ? n.nspname AND c.relkind IN ('r', 'p', 'v', 'm', 'f')
  LOOP
    EXECUTE format('ALTER %s %s OWNER TO %I', r.kind, r.obj, r.owner);
  END LOOP;
  FOR r IN
    SELECT p.oid::regprocedure AS obj, owner_of ->> n.nspname AS owner, CASE p.prokind WHEN 'p' THEN 'PROCEDURE' WHEN 'a' THEN 'AGGREGATE' ELSE 'FUNCTION' END AS kind
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE owner_of ? n.nspname
  LOOP
    EXECUTE format('ALTER %s %s OWNER TO %I', r.kind, r.obj, r.owner);
  END LOOP;
  FOR r IN
    SELECT t.oid::regtype AS obj, owner_of ->> n.nspname AS owner
    FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE owner_of ? n.nspname AND t.typtype IN ('c', 'e', 'd', 'r') AND (t.typrelid = 0 OR (SELECT relkind FROM pg_class WHERE oid = t.typrelid) = 'c')
  LOOP
    EXECUTE format('ALTER TYPE %s OWNER TO %I', r.obj, r.owner);
  END LOOP;
END $$;
SQL

(cd "$stage" && PATH="$stage/bin:$PATH" HAF_INSTALL_LOCK_HELD=1 bash scripts/install_app.sh --log-file=STDOUT)
