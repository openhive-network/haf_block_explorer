#!/usr/bin/env python3
"""tests/regression against the run's synced clone, with the expected data loaded in bulk.

    hafbe_regression.py OUT_DIR

What tests/regression/run_test.sh --type=all does in CI's regression-test, step
for step: install the hafbe_test schema (install_test_schema.sh --url), load
the hived snapshots at block 5000000 (accounts_dump.json.gz,
witnesses_dump.json.gz) through hafbe_test.load_expected_account_stats /
load_expected_witness_props, run hafbe_test.compare_accounts() (search path
hafbe_app), hafbe_test.compare_witnesses() (search path hafbe_bal) and
hafbe_test.compare_wallet_stats() and hafbe_test.compare_account_ops_count(), and
fail when hafbe_test.differing_accounts, differing_witnesses, differing_wallet_days
or differing_ops_counts has rows.

The one difference is the loading: load_expected_data.py calls the load
function once per record, one round trip each (92,462 accounts), which takes
most of an hour when the database is not local. Here the records are copied
into a temporary table in one COPY and loaded by one SELECT; the SQL functions
that load and compare are the tree's own.

Writes OUT_DIR/regression.xml (one junit case per comparison).
"""
import gzip
import io
import json
import os
import subprocess
import sys
import time
from xml.sax.saxutils import escape, quoteattr

import psycopg2

HERE = os.path.dirname(os.path.abspath(__file__))
REGRESSION = os.path.join(HERE, "..", "tests", "regression")

KINDS = [
    # name, dump, records path, load function, expected table, differing table, compare, search path
    ("account", "accounts_dump.json.gz", ("result", "accounts"), "hafbe_test.load_expected_account_stats",
     "hafbe_test.expected_account_stats", "hafbe_test.differing_accounts", "hafbe_test.compare_accounts()",
     "hafbe_app"),
    ("witness", "witnesses_dump.json.gz", ("result",), "hafbe_test.load_expected_witness_props",
     "hafbe_test.expected_witness_props", "hafbe_test.differing_witnesses", "hafbe_test.compare_witnesses()",
     "hafbe_bal"),
]


def records(dump: str, path: tuple[str, ...]) -> list:
    with gzip.open(os.path.join(REGRESSION, dump), "rt", encoding="utf-8") as handle:
        data = json.load(handle)
    for key in path:
        data = data[key]
    return data


def run_kind(conn, kind) -> tuple[bool, str]:
    name, dump, path, load, expected, differing, compare, search_path = kind
    rows = records(dump, path)
    if not rows:
        return False, f"no {name} records in {dump}"
    lines = "".join(json.dumps(row).replace("\\", "\\\\") + "\n" for row in rows)
    with conn.cursor() as cur:
        cur.execute(f"TRUNCATE {expected}; TRUNCATE {differing};")
        cur.execute("CREATE TEMP TABLE regression_input (record jsonb) ON COMMIT DROP")
        cur.copy_expert("COPY regression_input (record) FROM STDIN", io.StringIO(lines))
        cur.execute(f"SELECT {load}(record) FROM regression_input")
        cur.execute(f"SET search_path TO {search_path}")
        cur.execute(f"SELECT {compare}")
        cur.execute(f"SELECT count(*) FROM {differing}")
        count = cur.fetchone()[0]
        detail = ""
        if count:
            cur.execute(f"SELECT * FROM {differing} LIMIT 20")
            cols = [d[0] for d in cur.description]
            detail = "\n".join(str(dict(zip(cols, r))) for r in cur.fetchall())
        cur.execute("RESET search_path")
    conn.commit()
    if count:
        return False, f"{count} of {len(rows)} {name} records differ from the hived snapshot:\n{detail}"
    return True, f"all {len(rows)} {name} records match the hived snapshot"


def run_wallet_stats(conn) -> tuple[bool, str]:
    with conn.cursor() as cur:
        cur.execute("TRUNCATE hafbe_test.differing_wallet_days")
        cur.execute("SELECT hafbe_test.compare_wallet_stats()")
        cur.execute("SELECT count(*) FROM hafbe_app.wallet_stats_by_day")
        days = cur.fetchone()[0]
        cur.execute("SELECT day, stored, recomputed FROM hafbe_test.differing_wallet_days ORDER BY day LIMIT 20")
        differing = cur.fetchall()
    conn.commit()
    if differing:
        detail = "\n".join(f"{day}: stored {stored}, recomputed {recomputed}" for day, stored, recomputed in differing)
        return False, f"wallet_stats_by_day differs from account_parameters on these days (first 20):\n{detail}"
    return True, f"all {days} wallet_stats_by_day rows match account_parameters"



def run_ops_count(conn) -> tuple[bool, str]:
    with conn.cursor() as cur:
        cur.execute("TRUNCATE hafbe_test.differing_ops_counts")
        cur.execute("SELECT hafbe_test.compare_account_ops_count()")
        cur.execute("SELECT count(*) FROM hafbe_app.account_ops_count")
        accounts = cur.fetchone()[0]
        cur.execute("SELECT account_id, stored, recomputed FROM hafbe_test.differing_ops_counts ORDER BY account_id LIMIT 20")
        differing = cur.fetchall()
    conn.commit()
    if differing:
        detail = "\n".join(f"account {a}: stored {stored}, recomputed {recomputed}" for a, stored, recomputed in differing)
        return False, f"account_ops_count differs from account_operations for these accounts (first 20):\n{detail}"
    if not accounts:
        return False, "account_ops_count is empty"
    return True, f"all {accounts} account_ops_count rows match account_operations"

def main(out: str) -> int:
    url = os.environ["HAFBE_TEST_DB_URL"]
    subprocess.run(["bash", os.path.join(REGRESSION, "install_test_schema.sh"), f"--url={url}"], check=True)
    cases = []
    with psycopg2.connect(url) as conn:
        for kind in KINDS:
            t0 = time.monotonic()
            ok, message = run_kind(conn, kind)
            print(("PASS " if ok else "FAIL ") + message)
            cases.append((kind[0], ok, message, time.monotonic() - t0))
        t0 = time.monotonic()
        ok, message = run_wallet_stats(conn)
        print(("PASS " if ok else "FAIL ") + message)
        cases.append(("wallet_stats", ok, message, time.monotonic() - t0))
        t0 = time.monotonic()
        ok, message = run_ops_count(conn)
        print(("PASS " if ok else "FAIL ") + message)
        cases.append(("ops_count", ok, message, time.monotonic() - t0))
    with open(os.path.join(out, "regression.xml"), "w", encoding="utf-8") as handle:
        failures = sum(1 for c in cases if not c[1])
        handle.write('<?xml version="1.0" encoding="UTF-8"?>\n')
        handle.write(f'<testsuite name="regression" tests="{len(cases)}" failures="{failures}" errors="0">\n')
        for name, ok, message, seconds in cases:
            head = f"<testcase classname=\"regression\" name={quoteattr(name)} time=\"{seconds:.1f}\">"
            fail = "" if ok else f"<failure message={quoteattr(message.splitlines()[0])}>{escape(message)}</failure>"
            handle.write(f"{head}{fail}</testcase>\n")
        handle.write("</testsuite>\n")
    return 0 if all(c[1] for c in cases) else 1


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(f"usage: {sys.argv[0]} OUT_DIR")
    sys.exit(main(sys.argv[1]))
