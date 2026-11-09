"""PostgREST's own parameters keep their meaning through the rewriter.

hive.rpc_form moves to the form body only the parameters a function declares
(endpoints/rpc_arguments.lua); every other parameter (a column filter, select, order,
limit, offset) stays in the URL, where it still shapes the result.
"""
import pathlib
import re
from typing import Any

from common import Answer, direct_get, direct_post, postgrest_code, rewriter_post, via_rewriter

ENDPOINTS = pathlib.Path(__file__).resolve().parents[2] / "endpoints"


def _signatures() -> dict[str, set[str]]:
    signature = re.compile(r"CREATE OR REPLACE FUNCTION hafbe_endpoints\.(\w+)\s*\((.*?)\)\s*RETURNS",
                           re.S | re.I)
    found: dict[str, set[str]] = {}
    for sql in ENDPOINTS.rglob("*.sql"):
        for fn, params in signature.findall(sql.read_text(encoding="utf-8")):
            found[fn] = set(re.findall(r'"([^"]+)"', re.sub(r"--[^\n]*", "", params)))
    return found


def _argument_map() -> dict[str, set[str]]:
    lua = (ENDPOINTS / "rpc_arguments.lua").read_text(encoding="utf-8")
    return {fn: set(re.findall(r'\["([^"]+)"\] = true', fields))
            for fn, fields in re.findall(r'^\s*\["([^"]+)"\] = \{(.*)\},$', lua, re.M)}


def test_argument_map_matches_endpoint_signatures() -> None:
    """A parameter missing from the map stays in the URL, where an operator-prefixed value
    is read as a filter again: the map must be regenerated (scripts/openapi_rewrite.sh)
    with every signature change."""
    signatures, mapped = _signatures(), _argument_map()
    assert len(mapped) >= 20, f"found only {len(mapped)} functions in {ENDPOINTS / 'rpc_arguments.lua'}"
    assert not set(mapped) - set(signatures), set(mapped) - set(signatures)
    stale = {fn: sorted(signatures[fn] ^ names) for fn, names in mapped.items() if signatures[fn] != names}
    assert not stale, stale
    # The OpenAPI root document is the only endpoint function without a REST route.
    assert set(signatures) - set(mapped) == {"root"}, set(signatures) - set(mapped)


def _rows(ans: Answer) -> list[Any]:
    status, body = ans
    assert status == 200, ans
    assert isinstance(body, list), ans
    return body


def test_column_filter_on_function_without_arguments() -> None:
    full = _rows(via_rewriter("/hardforks"))
    assert any(r["hardfork_num"] == 2 for r in full), full
    got = via_rewriter("/hardforks", {"hardfork_num": "eq.2"})
    assert _rows(got) == [r for r in full if r["hardfork_num"] == 2]
    assert got == direct_get("get_hardforks", "hardfork_num=eq.2")


def test_column_filter_beside_function_arguments() -> None:
    args = {"granularity": "daily", "direction": "asc", "to-block": "100000"}
    full = _rows(via_rewriter("/transaction-statistics", args))
    counts = sorted(r["trx_count"] for r in full)
    threshold = counts[len(counts) // 2]
    want_rows = [r for r in full if r["trx_count"] > threshold]
    assert 0 < len(want_rows) < len(full), counts
    got = via_rewriter("/transaction-statistics", {**args, "trx_count": f"gt.{threshold}"})
    assert _rows(got) == want_rows
    assert got == direct_post("get_transaction_statistics", args, query={"trx_count": f"gt.{threshold}"})


def test_limit_trims_rows() -> None:
    full = _rows(via_rewriter("/hardforks"))
    assert len(full) >= 3, full
    got = via_rewriter("/hardforks", {"limit": "2"})
    assert _rows(got) == full[:2]
    assert got == direct_get("get_hardforks", "limit=2")


def test_offset_and_limit() -> None:
    full = _rows(via_rewriter("/hardforks"))
    got = via_rewriter("/hardforks", [("offset", "1"), ("limit", "2")])
    assert _rows(got) == full[1:3]
    assert got == direct_get("get_hardforks", "offset=1&limit=2")


def test_order_and_select() -> None:
    got = via_rewriter("/hardforks", [("select", "hardfork_num"), ("order", "hardfork_num.desc"), ("limit", "2")])
    full = _rows(via_rewriter("/hardforks"))
    want = [{"hardfork_num": r["hardfork_num"]} for r in sorted(full, key=lambda r: -r["hardfork_num"])[:2]]
    assert _rows(got) == want
    assert got == direct_get("get_hardforks", "select=hardfork_num&order=hardfork_num.desc&limit=2")


def test_limit_beside_function_arguments() -> None:
    params = [("granularity", "daily"), ("direction", "asc"), ("to-block", "100000"), ("limit", "2")]
    full = _rows(via_rewriter("/transaction-statistics", params[:-1]))
    assert len(full) >= 2, full
    got = via_rewriter("/transaction-statistics", params)
    assert _rows(got) == full[:2]
    assert got == direct_post("get_transaction_statistics",
                              {"granularity": "daily", "direction": "asc", "to-block": "100000"},
                              query={"limit": "2"})


def test_limit_beside_operator_prefixed_argument() -> None:
    got = via_rewriter("/accounts/not.existing/proxy-power", {"limit": "1"})
    want = direct_post("get_account_proxies_power", {"account-name": "not.existing"}, query={"limit": "1"})
    assert postgrest_code(want) not in ("PGRST100", "PGRST202"), want
    assert got == want


def test_calls_without_arguments_and_json_posts_unchanged() -> None:
    assert via_rewriter("/version") == direct_post("get_hafbe_version", {})
    assert via_rewriter("/hardforks") == direct_get("get_hardforks", "")
    # Only GETs and HEADs are converted: a JSON POST goes through as sent.
    args = {"account-name": "eq.blocktrades"}
    got = rewriter_post("/get_witness", args)
    want = direct_post("get_witness", args)
    assert postgrest_code(want) not in ("PGRST100", "PGRST202"), want
    assert got == want
