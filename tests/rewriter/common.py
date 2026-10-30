"""Calls through the postgrest-rewriter image and straight to PostgREST.

The rewriter (docker/haf_block_explorer_nginx.conf.template) is what serves the public
REST paths. These tests compare its answers with a direct JSON POST to the function,
which PostgREST always reads as arguments, whatever the values start with.

HAFBE_ADDRESS is the host of both; HAFBE_PORT is PostgREST's port and REWRITER_PORT the
rewriter's (docker/docker-compose-test.yml, profile "rewriter"). POSTGREST_URL and
REWRITER_URL override either base URL whole.
"""
import base64
import os

import requests

HOST = os.environ.get("HAFBE_ADDRESS", "localhost")
POSTGREST = os.environ.get("POSTGREST_URL") or f"http://{HOST}:{os.environ.get('HAFBE_PORT', '3000')}"
REWRITER = os.environ.get("REWRITER_URL") or f"http://{HOST}:{os.environ.get('REWRITER_PORT', '3080')}"
TIMEOUT_S = 30


def answer(resp: requests.Response):
    """Status and decoded body, the part of an answer a client sees."""
    try:
        body = resp.json()
    except ValueError:
        body = resp.text
    return resp.status_code, body


def via_rewriter(path: str, params=None):
    """GET a public REST path through the rewriter."""
    return answer(requests.get(REWRITER + path, params=params, timeout=TIMEOUT_S))


def rewriter_post(path: str, args: dict):
    """JSON POST through the rewriter."""
    return answer(requests.post(REWRITER + path, json=args,
                                headers={"Accept": "application/json"}, timeout=TIMEOUT_S))


def direct_post(function: str, args: dict, query=None):
    """JSON POST to the function; every field is an argument."""
    return answer(requests.post(f"{POSTGREST}/rpc/{function}", json=args, params=query,
                                headers={"Accept": "application/json"}, timeout=TIMEOUT_S))


def direct_get(function: str, query: str):
    """GET straight to PostgREST, the way the rewriter forwarded calls before the form POST."""
    return answer(requests.get(f"{POSTGREST}/rpc/{function}?{query}", timeout=TIMEOUT_S))


def path_filter(*filters: str) -> str:
    """The array the rewriter builds from path-filter parameters (base64 of each)."""
    return "{" + ",".join(base64.b64encode(f.encode()).decode() for f in filters) + "}"


def postgrest_code(ans):
    status, body = ans
    return body.get("code") if isinstance(body, dict) else None
