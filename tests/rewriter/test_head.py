"""A HEAD through the rewriter answers with its GET's status and no body.

hive.rpc_form forwards a HEAD as a POST; were the POST's body sent, the next answer on a
keep-alive connection would start inside it. Each case sends the HEAD and then a GET on
one connection and checks that the GET's answer is read whole and as sent alone.
"""
import http.client
import json
import socket
import urllib.parse

import pytest

from common import REWRITER, TIMEOUT_S, via_rewriter

PATHS = ["/accounts/blocktrades", "/accounts/not.blocktrades", "/witnesses/blocktrades/voters/count",
         "/hardforks?hardfork_num=eq.2", "/version"]


def _address() -> tuple[str, int]:
    url = urllib.parse.urlsplit(REWRITER)
    if not url.hostname:
        raise ValueError(f"no host in the rewriter URL {REWRITER!r}")
    return url.hostname, url.port or 80


def _connection() -> http.client.HTTPConnection:
    host, port = _address()
    return http.client.HTTPConnection(host, port, timeout=TIMEOUT_S)


@pytest.mark.parametrize("path", PATHS)
def test_head_then_get_on_one_connection(path: str) -> None:
    want_status, want_body = via_rewriter(path)
    conn = _connection()
    try:
        conn.request("HEAD", path)
        head = conn.getresponse()
        assert head.read() == b""
        assert head.status == want_status
        conn.request("GET", path)
        get = conn.getresponse()
        assert get.status == want_status
        assert json.loads(get.read()) == want_body
    finally:
        conn.close()


def test_head_sends_no_body_bytes() -> None:
    """http.client never reads a HEAD's body, so read the raw stream: after the HEAD's
    headers the connection carries nothing until the next request."""
    host, port = _address()
    with socket.create_connection((host, port), timeout=TIMEOUT_S) as sock:
        sock.sendall(f"HEAD /accounts/blocktrades HTTP/1.1\r\nHost: {host}\r\n\r\n".encode())
        data = b""
        while b"\r\n\r\n" not in data:
            chunk = sock.recv(65536)
            assert chunk, data
            data += chunk
        headers, rest = data.split(b"\r\n\r\n", 1)
        assert headers.startswith(b"HTTP/1.1 200"), headers
        assert rest == b""
        sock.settimeout(2)
        with pytest.raises(socket.timeout):
            extra = sock.recv(65536)
            pytest.fail(f"bytes after the HEAD's headers: {extra!r}")
