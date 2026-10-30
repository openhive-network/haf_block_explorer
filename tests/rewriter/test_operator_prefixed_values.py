"""A REST value that starts with a PostgREST operator prefix reaches its function verbatim (#169).

PostgREST reads such a GET argument as a filter (PGRST100, or the argument dropped and
PGRST202). The rewriter forwards GETs as form POSTs, so each case here must answer through
the rewriter exactly as a direct JSON POST of the same arguments does.

Every TEXT argument of every endpoint is covered: the account names and free text the
rewrite rules take from the path, and every TEXT query parameter. Equality with the oracle
proves the value was read as an argument; where an endpoint's answer does not depend on the
value on this lane (e.g. `search` over the 5M lane's empty proposal tables), it proves only
that. test_value_arrives_unchanged checks the value itself, through an endpoint that echoes it.
"""
import pytest

from common import direct_post, path_filter, postgrest_code, via_rewriter

VALUES = ["not.existing", "eq.blocktrades", "in.(gtg)", "like.gtg*", "is.null", "fts.gtg"]

# (public path with {v} where the value goes in the path, function, its fixed arguments,
#  the argument {v} is, and whether {v} is a query parameter instead of a path segment)
PATH, QUERY = False, True
CASES = [
    ("/accounts/{v}", "get_account", {}, "account-name", PATH),
    ("/accounts/{v}/authority", "get_account_authority", {}, "account-name", PATH),
    ("/accounts/{v}/proxy-power", "get_account_proxies_power", {}, "account-name", PATH),
    ("/accounts/{v}/comment-permlinks", "get_comment_permlinks", {}, "account-name", PATH),
    ("/accounts/{v}/operations/comments/x", "get_comment_operations", {"permlink": "x"}, "account-name", PATH),
    ("/accounts/gtg/operations/comments/{v}", "get_comment_operations", {"account-name": "gtg"}, "permlink", PATH),
    ("/witnesses/{v}", "get_witness", {}, "account-name", PATH),
    ("/witnesses/{v}/voters", "get_witness_voters", {}, "account-name", PATH),
    ("/witnesses/{v}/voters/count", "get_witness_voters_num", {}, "account-name", PATH),
    ("/witnesses/{v}/votes/history", "get_witness_votes_history", {}, "account-name", PATH),
    ("/input-type/{v}", "get_input_type", {}, "input-value", PATH),
    ("/witnesses/blocktrades/voters", "get_witness_voters", {"account-name": "blocktrades"}, "voter-name", QUERY),
    ("/witnesses/blocktrades/votes/history", "get_witness_votes_history", {"account-name": "blocktrades"}, "voter-name", QUERY),
    ("/witnesses/blocktrades/votes/history", "get_witness_votes_history", {"account-name": "blocktrades"}, "from-block", QUERY),
    ("/witnesses/blocktrades/votes/history", "get_witness_votes_history", {"account-name": "blocktrades"}, "to-block", QUERY),
    ("/accounts/gtg/comment-permlinks", "get_comment_permlinks", {"account-name": "gtg"}, "from-block", QUERY),
    ("/accounts/gtg/comment-permlinks", "get_comment_permlinks", {"account-name": "gtg"}, "to-block", QUERY),
    ("/accounts/gtg/operations/comments/x", "get_comment_operations", {"account-name": "gtg", "permlink": "x"}, "operation-types", QUERY),
    ("/proposals", "get_proposals", {}, "creator", QUERY),
    ("/proposals", "get_proposals", {}, "voter", QUERY),
    ("/proposals", "get_proposals", {}, "search", QUERY),
    ("/proposals", "get_proposals", {}, "proposal-ids", QUERY),
    ("/proposals/votes", "get_proposal_votes", {}, "voter", QUERY),
    ("/proposals/1/votes/history", "get_proposal_votes_history", {"proposal-id": "1"}, "voter-name", QUERY),
    ("/proposals/1/votes/history", "get_proposal_votes_history", {"proposal-id": "1"}, "from-block", QUERY),
    ("/proposals/1/votes/history", "get_proposal_votes_history", {"proposal-id": "1"}, "to-block", QUERY),
    ("/block-search", "get_block_by_op", {}, "account-name", QUERY),
    ("/block-search", "get_block_by_op", {}, "operation-types", QUERY),
    ("/block-search", "get_block_by_op", {}, "from-block", QUERY),
    ("/block-search", "get_block_by_op", {}, "to-block", QUERY),
    ("/operation-type-statistics", "get_operation_type_statistics", {}, "op-types", QUERY),
    ("/operation-type-statistics", "get_operation_type_statistics", {}, "from-block", QUERY),
    ("/operation-type-statistics", "get_operation_type_statistics", {}, "to-block", QUERY),
    ("/transaction-statistics", "get_transaction_statistics", {}, "from-block", QUERY),
    ("/transaction-statistics", "get_transaction_statistics", {}, "to-block", QUERY),
    ("/total_wallet_addresses", "get_total_wallet_addresses", {}, "from-block", QUERY),
    ("/total_wallet_addresses", "get_total_wallet_addresses", {}, "to-block", QUERY),
    ("/hbd/status", "get_hbd_status", {}, "from-block", QUERY),
    ("/hbd/status", "get_hbd_status", {}, "to-block", QUERY),
    ("/operation-type-counts", "get_latest_blocks", {}, "block-num", QUERY),
    # The catch-all rule (/<function> -> /rpc/<function>) with the arguments in the query string.
    ("/get_witness", "get_witness", {}, "account-name", QUERY),
    ("/get_input_type", "get_input_type", {}, "input-value", QUERY),
]


def _id(case):
    path, _function, _fixed, arg, in_query = case
    return f"{path}?{arg}" if in_query else path


@pytest.mark.parametrize("value", VALUES)
@pytest.mark.parametrize("case", CASES, ids=_id)
def test_value_reaches_function_verbatim(case, value):
    path, function, fixed, arg, in_query = case
    if in_query:
        got = via_rewriter(path, {arg: value})
    else:
        got = via_rewriter(path.replace("{v}", value))
    want = direct_post(function, {**fixed, arg: value})
    # The oracle itself must have called the function with the argument.
    assert postgrest_code(want) not in ("PGRST100", "PGRST202"), want
    assert got == want


@pytest.mark.parametrize("value", VALUES)
@pytest.mark.parametrize("path", ["/input-type/{v}", "/get_input_type?input-value={v}"])
def test_value_arrives_unchanged(path, value):
    """get_input_type answers an input that matches nothing with that input, so the value
    the function received is visible: as a path segment and as a query parameter."""
    if "?" in path:
        status, body = via_rewriter(path.split("?")[0], {"input-value": value})
    else:
        status, body = via_rewriter(path.replace("{v}", value))
    assert status == 200, body
    assert body["input_value"] == [value], body


def test_block_search_path_filter_unchanged():
    """The path-filter encoding (the template's Lua above the rewrite rules) still reaches
    get_block_by_op, now in the form body, together with an operator-prefixed argument."""
    def search(author):
        params = [("operation-types", "1"), ("account-name", "blocktrades"),
                  ("path-filter", f"value.author={author}")]
        got = via_rewriter("/block-search", params)
        want = direct_post("get_block_by_op", {
            "operation-types": "1", "account-name": "blocktrades",
            "path-filter": path_filter(f"value.author={author}")})
        assert want[0] == 200, want
        assert got == want
        return got

    # A filter that matches nothing answers differently, so the filter was applied.
    assert search("blocktrades") != search("no-such-author")

    got = via_rewriter("/block-search", [("operation-types", "1"), ("account-name", "not.existing"),
                                         ("path-filter", "value.author=not.existing")])
    want = direct_post("get_block_by_op", {
        "operation-types": "1", "account-name": "not.existing",
        "path-filter": path_filter("value.author=not.existing")})
    assert postgrest_code(want) not in ("PGRST100", "PGRST202"), want
    assert got == want
