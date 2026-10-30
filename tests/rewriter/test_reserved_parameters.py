"""PostgREST's own parameters keep their meaning through the rewriter (#169).

The rewriter moves a GET's function arguments into a form body but keeps PostgREST's
reserved parameters (select, columns, on_conflict, ...limit, ...offset, ...order, ...and,
...or) in the URL, so they still shape the result instead of becoming unknown arguments.
"""
from common import direct_get, direct_post, postgrest_code, rewriter_post, via_rewriter


def _rows(ans):
    status, body = ans
    assert status == 200, ans
    assert isinstance(body, list), ans
    return body


def test_limit_trims_rows():
    full = _rows(via_rewriter("/hardforks"))
    assert len(full) >= 3, full
    got = via_rewriter("/hardforks", {"limit": "2"})
    assert _rows(got) == full[:2]
    assert got == direct_get("get_hardforks", "limit=2")


def test_offset_and_limit():
    full = _rows(via_rewriter("/hardforks"))
    got = via_rewriter("/hardforks", [("offset", "1"), ("limit", "2")])
    assert _rows(got) == full[1:3]
    assert got == direct_get("get_hardforks", "offset=1&limit=2")


def test_order_and_select():
    got = via_rewriter("/hardforks", [("select", "hardfork_num"), ("order", "hardfork_num.desc"), ("limit", "2")])
    full = _rows(via_rewriter("/hardforks"))
    want = [{"hardfork_num": r["hardfork_num"]} for r in sorted(full, key=lambda r: -r["hardfork_num"])[:2]]
    assert _rows(got) == want
    assert got == direct_get("get_hardforks", "select=hardfork_num&order=hardfork_num.desc&limit=2")


def test_limit_beside_function_arguments():
    params = [("granularity", "daily"), ("direction", "asc"), ("to-block", "100000"), ("limit", "2")]
    full = _rows(via_rewriter("/transaction-statistics", params[:-1]))
    assert len(full) >= 2, full
    got = via_rewriter("/transaction-statistics", params)
    assert _rows(got) == full[:2]
    assert got == direct_post("get_transaction_statistics",
                              {"granularity": "daily", "direction": "asc", "to-block": "100000"},
                              query={"limit": "2"})


def test_limit_beside_operator_prefixed_argument():
    got = via_rewriter("/accounts/not.existing/proxy-power", {"limit": "1"})
    want = direct_post("get_account_proxies_power", {"account-name": "not.existing"}, query={"limit": "1"})
    assert postgrest_code(want) not in ("PGRST100", "PGRST202"), want
    assert got == want


def test_calls_without_arguments_and_json_posts_unchanged():
    assert via_rewriter("/version") == direct_post("get_hafbe_version", {})
    assert via_rewriter("/hardforks") == direct_get("get_hardforks", "")
    # Only GETs are converted: a JSON POST goes through as sent.
    args = {"account-name": "eq.blocktrades"}
    got = rewriter_post("/get_witness", args)
    want = direct_post("get_witness", args)
    assert postgrest_code(want) not in ("PGRST100", "PGRST202"), want
    assert got == want
