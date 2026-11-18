#!/usr/bin/env python3
"""Run a tavern pattern suite against PostgREST over the run's synced clone.

    hafbe_tavern.py OUT_DIR [patterns-mainnet|patterns-mock]

As CI's pattern-test runs tests/tavern/patterns-mainnet (the default), against
haf_block_explorer, balance_tracker and reputation_tracker synced to block
5000000 by run-checks.sh's `sync` step; and as CI's pattern-test-with-mock-data
runs tests/tavern/patterns-mock, once run-checks.sh's `tavern-mock` step has put
CI's mock data on the clone. Each test POSTs to /rpc/<function> at
HAFBE_ADDRESS:HAFBE_PORT and hive/tests_api's validate_response compares the
answer with the test's .pat.json. The comparator writes each answer
(.out.json) beside its test, so the tests run from a copy in OUT_DIR/tavern,
which keeps those answers as artefacts; a run of one suite keeps the other's.

Writes OUT_DIR/tavern.xml (patterns-mainnet) or OUT_DIR/tavern-mock.xml
(patterns-mock), one junit case per tavern test, and exits with pytest's status.
"""
import json
import os
import shutil
import subprocess
import sys
import urllib.request

from postgrest import serving

HERE = os.path.dirname(os.path.abspath(__file__))
TAVERN_SOURCE = os.path.join(HERE, "..", "tests", "tavern")
# Each suite's report name: OUT_DIR/<name>.xml and its PostgREST log, postgrest-<name>.log.
REPORTS = {"patterns-mainnet": "tavern", "patterns-mock": "tavern-mock"}
WORKERS = os.environ.get("HAFBE_TAVERN_WORKERS", "4")


def warm_up(base: str) -> None:
    """CI's pattern-test warms this endpoint first; its first call is the slowest."""
    request = urllib.request.Request(
        base + "/rpc/get_witness_votes_history",
        data=json.dumps({"account-name": "blocktrades", "page-size": 5}).encode(),
        headers={"Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=15):
            pass
    except OSError as err:
        print(f"warm-up call failed (ignored): {err}")


def main(out: str, suite: str) -> int:
    os.makedirs(out, exist_ok=True)
    tavern_dir = os.path.abspath(os.path.join(out, "tavern"))
    shutil.rmtree(os.path.join(tavern_dir, suite), ignore_errors=True)
    shutil.copytree(TAVERN_SOURCE, tavern_dir, dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns("*.out.json"))
    report = REPORTS[suite]
    with serving(os.path.join(out, f"postgrest-{report}.log")) as base:
        host, port = base.removeprefix("http://").rsplit(":", 1)
        warm_up(base)
        # validate_response resolves each test's .pat.json/.out.json against TAVERN_DIR,
        # which CI sets to the suite directory.
        env = dict(os.environ, HAFBE_ADDRESS=host, HAFBE_PORT=port,
                   TAVERN_DIR=os.path.join(tavern_dir, suite))
        return subprocess.run(
            [sys.executable, "-m", "pytest", "-n", WORKERS, "-p", "no:cacheprovider",
             "--junitxml", os.path.abspath(os.path.join(out, f"{report}.xml")), suite],
            cwd=tavern_dir, env=env, check=False,
        ).returncode


if __name__ == "__main__":
    if len(sys.argv) not in (2, 3) or (len(sys.argv) == 3 and sys.argv[2] not in REPORTS):
        sys.exit(f"usage: {sys.argv[0]} OUT_DIR [{'|'.join(REPORTS)}]")
    sys.exit(main(sys.argv[1], sys.argv[2] if len(sys.argv) == 3 else "patterns-mainnet"))
