#!/usr/bin/env python3
"""Run the tavern pattern tests against PostgREST over the run's synced clone.

    hafbe_tavern.py OUT_DIR

As CI's pattern-test runs them (tests/tavern/patterns-mainnet), against
haf_block_explorer, balance_tracker and reputation_tracker synced to block
5000000 by run-checks.sh's `sync` step: each test POSTs to /rpc/<function> at
HAFBE_ADDRESS:HAFBE_PORT and hive/tests_api's validate_response compares the
answer with the test's .pat.json. The comparator writes each answer
(.out.json) beside its test, so the tests run from a copy in OUT_DIR/tavern,
which keeps those answers as artefacts.

tests/tavern/patterns-mock is not run: it needs CI's mock data
(sync_with_mock_data), which the shared HAF does not have.

Writes OUT_DIR/tavern.xml (one junit case per tavern test) and exits with
pytest's status.
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
SUITE = "patterns-mainnet"
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


def main(out: str) -> int:
    os.makedirs(out, exist_ok=True)
    tavern_dir = os.path.abspath(os.path.join(out, "tavern"))
    shutil.rmtree(tavern_dir, ignore_errors=True)
    shutil.copytree(TAVERN_SOURCE, tavern_dir, ignore=shutil.ignore_patterns("*.out.json"))
    with serving(os.path.join(out, "postgrest-tavern.log")) as base:
        host, port = base.removeprefix("http://").rsplit(":", 1)
        warm_up(base)
        # validate_response resolves each test's .pat.json/.out.json against TAVERN_DIR,
        # which CI sets to the suite directory.
        env = dict(os.environ, HAFBE_ADDRESS=host, HAFBE_PORT=port,
                   TAVERN_DIR=os.path.join(tavern_dir, SUITE))
        return subprocess.run(
            [sys.executable, "-m", "pytest", "-n", WORKERS, "-p", "no:cacheprovider",
             "--junitxml", os.path.abspath(os.path.join(out, "tavern.xml")), SUITE],
            cwd=tavern_dir, env=env, check=False,
        ).returncode


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(f"usage: {sys.argv[0]} OUT_DIR")
    sys.exit(main(sys.argv[1]))
