# haf_block_explorer under AIDEV

AIDEV verifies changes to this repository through the slots in `project.yaml`,
integrates them into `aidev/integration`, and people merge that into `develop`
through merge requests (as in hive/HAfAH and hive/hivemind). GitLab CI doesn't run
for AIDEV branches (`ai/*`, `session/*`, pushes to `aidev/integration`); see
`.gitlab-ci.yml` `workflow:`. Merge `aidev/integration` keeping the source branch:
the project deletes source branches on merge by default, and AIDEV's workflows
fork from that branch.

## Suites

`.aidev/run-checks.sh <suite> <step>...` runs the named steps and writes
`test-results/<suite>/junit.xml`, one test case per step, with the step's log tail as
the failure body. `regression` also writes one case per comparison
(`regression.xml`), `tavern` one per test (`tavern.xml`).

| Step | What | CI job it stands for |
|---|---|---|
| `shellcheck` | ShellCheck at its default severity on every `*.sh` outside `submodules/` | `lint_bash_scripts` (error severity; the tree is clean at the default) |
| `sqlfluff` | sqlfluff 2.1.4 with `.sqlfluff` on the tree; fails on a violation in a file not listed in `sqlfluff-baseline` | `lint_sql_scripts` |
| `sql-registered` | every `.sql` file under `db/`, `backend/` and `endpoints/` is applied by `scripts/install_app.sh`, except those `sql-unregistered` lists (a file it misses never reaches a database) | — |
| `install` | a per-run copy-on-write clone of the shared HAF (below); HAfAH into it from the runtime image's `/opt/hafah`, then `scripts/install_app.sh --blocksearch-indexes=true` (as CI's compose) as `haf_shared_consumer`: balance tracker into `hafbe_bal` and reputation tracker from `submodules/`, then haf_block_explorer | `sync` (its `hafah-install` and `backend-setup` services) |
| `reinstall` | `install_app.sh` over the installed apps, `scripts/uninstall_app.sh` (checks the `hafbe_*` schemas are gone), `install_app.sh` again | `setup-scripts-test` |
| `sync` | haf_block_explorer's block processing (with the balance tracker) and the reputation tracker's, to block 5000000 in the clone; then the witness votes cache, `hafbe_app.create_hafbe_indexes()` and `hive.app_restore_indexes('hafbe_app')` | `sync` + `wait-for-haf-be-startup.sh` |
| `regression` | `.aidev/hafbe_regression.py`: `tests/regression` against the synced clone, every account and witness compared with hived's snapshot at block 5000000, and `hafbe_app.wallet_stats_by_day` with the aggregate over `account_parameters` it caches | `regression-test` |
| `tavern` | `.aidev/hafbe_tavern.py`: `tests/tavern/patterns-mainnet` against PostgREST over the synced clone (`postgrest.py`, as `docker/docker-compose-test.yml` starts it), 4 xdist workers, run from a copy in `test-results/<suite>/tavern/` (the comparator writes each answer, `.out.json`, beside its test) | `pattern-test` |

| Slot | Steps | Shared HAF |
|---|---|---|
| quick, coverage | shellcheck, sqlfluff, sql-registered | no |
| full, canary | those plus install, reinstall, sync, regression, tavern | yes |
| baseline | install, reinstall, sync, regression, tavern | yes |

`static` and `system` are unbound: AIDEV runs neither for a project.

A full run takes 5 to 15 minutes, most of it the sync and the installs. The sync takes
about 4 minutes on an idle shared HAF and longer when other clones are syncing at the
same time (the reputation tracker is the long pole: a promote's baseline and canary
syncing together took over 10 minutes); each install is many `psql` calls, so it takes
longer the further the host is from the shared HAF. `canary` and `baseline` therefore
declare `timeout: 2400` (the canary's base wall is 900 s), and the processors run with a
`statement_timeout` of `HAFBE_SYNC_TIMEOUT_S` (1800 s) so that a run killed from
outside does not leave them syncing on the server.

**HAfAH.** haf_block_explorer's SQL calls `hafah_backend` (account ids, operation
bodies, paging), so HAfAH is installed first, as CI's compose does from the HAfAH image
`.gitlab-ci.yml` pins (`HAFAH_REGISTRY`/`HAFAH_VERSION`, HAfAH fe9aaf53). The runtime
image copies that image's sources to `/opt/hafah`; when `HAFAH_VERSION` moves, move
the `hafah` stage of `runtime/Dockerfile` with it and rebuild. `reinstall` leaves HAfAH
installed.

The install steps copy `db/ backend/ endpoints/ scripts/` and both submodules to a
scratch directory and write the three version files there (`git rev-parse HEAD`, or
`aidev` when the checkout has no usable git), because a workflow checkout may have no
`.git`. `install_app.sh` and `uninstall_app.sh` name database `haf_block_log`; the
staged copies name the run's clone instead. The submodules must be checked out.

**The sync.** The processors run the way `scripts/process_blocks.sh` and the
reputation tracker's run them without `haf_app_driver.py` (the `CALL ...main()` loop),
as `hafbe_owner` and `reptracker_owner`. `hafbe_app.main()` does not return when it
reaches its block limit: it waits for the next block. The step polls `hafd.contexts`
until `hafbe_app` and `hafbe_bal` are at 5000000 and stops it with
`hafbe_app.stopProcessing()`. hived, which builds the HAF indexes an app registers in
production, does not run in the shared HAF, so the step builds them with
`hive.app_restore_indexes` as `wait-for-haf-be-startup.sh` does.

**The regression loader.** `tests/regression/load_expected_data.py` makes one round
trip per record (92,462 accounts): most of an hour when the database is not on the
same host. `hafbe_regression.py` copies the records into a temporary table in one
`COPY` and loads them with one `SELECT` of the same `hafbe_test` functions; the
schema install, the comparisons and the verdict are `run_test.sh`'s.

**sqlfluff.** CI's `lint_sql_scripts` fails only on `code: L0..` lines, which sqlfluff
2.x never prints, so it has never failed. The tree had 64 violations in 6 files when
AIDEV was onboarded; `sqlfluff-baseline` lists those files, the step reports their
violations and fails on any elsewhere. Drop a file from the list once it is clean.

**`db/indexes.sql`** is not applied by `install_app.sh`: since 5b7b588 the HAF
indexes are registered by `hafbe_app.register_haf_indexes()` at the MASSIVE→LIVE
switch. `sql-unregistered` names it so `sql-registered` passes; delete the file or
the entry when that is settled.

### Not covered, and tests that need data the gates do not have

- `tests/tavern/patterns-mock` (CI's `pattern-test-with-mock-data`) needs CI's mock
  data (`sync_with_mock_data`: `docker/docker-compose-mocks.yml` fills the database
  with mock blocks and the processors sync over them). The shared HAF has the real
  chain to block 5000000 only, so these tests run in GitLab CI alone.
- `tests/performance` (JMeter), `scripts/python_api_package` tests and the advisory-lock
  skip test in CI's `sync` job stay in GitLab CI.

`patterns-mainnet` runs on the real chain to block 5000000, the data CI's
`pattern-test` uses, so a pattern's expected value can be made in a gate: write the
`.tavern.yaml` with a `.pat.json` (`{}` will do), run the `full` slot, read the answer
from `test-results/full/tavern/patterns-mainnet/<endpoint>/<test>.out.json`, check it
against independent data (hived's API, a block explorer) and copy it over the
`.pat.json`. An unchecked `.out.json` records whatever bug the change has as the
expected value. A pattern for `patterns-mock` can only come from CI's
`pattern-test-with-mock-data` artefacts.

## The shared HAF (`sandbox.external`)

The slots without `stack: false` declare `sandbox.external: [{name: haf, provider:
haf/haf}]`: a HAF replayed to block 5000000 that an AIDEV session of the `haf` project
hosts for every HAF app's checks. AIDEV hands the suite its address as
`AIDEV_EXTERNAL_HAF_HOST`/`_PORT` and lets the runtime container reach it and nothing
else; when it is down the slot is refused as environmental, naming the provider.

`run-checks.sh` connects as `haf_shared_consumer` (trusted from the fleet LAN, no
password) and, at the first step that needs it:

1. `select haf_shared.clone_run_database('<run id>')` in database `haf_shared` returns
   `run_<run id>`, a copy-on-write clone (about a second); the run id is
   `hafbe-<suite>-<UTC time>-<random>`, so concurrent runs never share a clone;
2. grants `CREATE, CONNECT` on the clone to `hafbe_owner`, `hafbe_user`,
   `btracker_owner`, `btracker_user`, `reptracker_owner`, `reptracker_user`,
   `hafah_owner` and `hafah_user`. The
   shared HAF creates these roles (hive/haf `.aidev/shared-haf/app-roles/`) and makes
   the consumer a member of the three owner roles, because the consumer cannot create
   roles;
3. installs from the staged copy, whose `db/builtin_roles.sql` files are empty and
   whose uninstall drops the schemas only (`DROP OWNED BY` the app's roles would revoke
   their grants on every other run's clone too, database privileges being
   cluster-wide);
4. on exit, pass or fail, `haf_shared.drop_run_database('<run id>')`; a clone a killed
   run leaves behind is reaped by the provider.

PostgREST connects to the clone as `haf_shared_consumer` with
`PGRST_DB_ANON_ROLE=hafbe_user`.

To run the stack checks by hand against the shared HAF (`aidev session status
haf-shared` shows its endpoint), with the submodules checked out:

```bash
image="$(grep -o 'registry[^"]*aidev-tests@sha256:[0-9a-f]*' .aidev/project.yaml)"
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/w" -w /w \
    -e AIDEV_EXTERNAL_HAF_HOST=<host> -e AIDEV_EXTERNAL_HAF_PORT=<port> "$image" \
    .aidev/run-checks.sh full shellcheck sqlfluff sql-registered install reinstall sync regression tavern
```

## The test runtime image (`runtime/`)

The checks run in a container with your uid: `python:3.14-alpine` (hive/tests_api needs
Python >= 3.14), the `postgrest` binary of `postgrest/postgrest:v16.4` (CI's test
compose file runs `latest`), `bash`, `git`, `psql` and `shellcheck` from Alpine's
repository, and pinned `tavern`, `pytest`, `pytest-xdist`, `psycopg2-binary`,
`sqlfluff` 2.1.4 (with `click` < 8.2, which it needs) and hive/tests_api
(`validate_response`, the tavern tests' comparator) at the commit the Dockerfile's
`TESTS_API_COMMIT` names, and HAfAH's SQL sources from CI's HAfAH image at
`/opt/hafah`; all bases pinned by digest, nothing installed at run time.

When `runtime/Dockerfile` changes, rebuild and re-pin **in the same commit**:

```bash
.aidev/runtime/build.sh --push   # registry digest if aidev-<input hash> exists, else build + push
# put the printed repo@sha256:<digest> into project.yaml environment.image
```

To build through a pull-through registry cache near the build host, set
`AIDEV_IMAGE_CACHE_BY_REGION` to `region=host:port` pairs, e.g.
`eu=cache.example.org:5001,*=cache2.example.org:5001`: a pair applies when its region is
a label of the host's FQDN, and `*` applies to any other host. Unset, the image is built
straight from the registries.
