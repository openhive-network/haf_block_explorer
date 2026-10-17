"""PostgREST over the installed haf_block_explorer schema, for the checks that call its API.

Started the way docker/docker-compose-test.yml starts it in CI (schema
hafbe_endpoints, anonymous role hafbe_user, extra search path hafbe_bal and
reptracker_app), on a free loopback port, connecting with HAFBE_TEST_DB_URL (the
run's clone of the shared HAF, as haf_shared_consumer, which switches to
hafbe_user through hafbe_owner).
"""
import contextlib
import json
import os
import socket
import subprocess
import time
import urllib.error
import urllib.request
from collections.abc import Iterator

STARTUP_TIMEOUT_S = 60


def _free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port: int = sock.getsockname()[1]
        return port


def _answers(base: str) -> bool:
    request = urllib.request.Request(
        base + "/rpc/get_hafbe_version", data=json.dumps({}).encode(),
        headers={"Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=5) as resp:
            status: int = resp.status
            return status == 200
    except (urllib.error.URLError, OSError):
        return False


@contextlib.contextmanager
def serving(log_path: str) -> Iterator[str]:
    """Run PostgREST for the duration of the block; yield its base URL.

    Its output goes to log_path. Raises RuntimeError when it exits or does not
    answer within STARTUP_TIMEOUT_S.
    """
    port = _free_port()
    base = f"http://127.0.0.1:{port}"
    env = dict(os.environ,
               PGRST_DB_URI=os.environ["HAFBE_TEST_DB_URL"],
               PGRST_DB_SCHEMA="hafbe_endpoints",
               PGRST_DB_ANON_ROLE="hafbe_user",
               PGRST_DB_EXTRA_SEARCH_PATH="hafbe_bal, reptracker_app",
               PGRST_DB_POOL="20",
               PGRST_DB_POOL_ACQUISITION_TIMEOUT="10",
               PGRST_SERVER_HOST="127.0.0.1",
               PGRST_SERVER_PORT=str(port))
    with open(log_path, "w") as log:
        proc = subprocess.Popen(["postgrest"], env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + STARTUP_TIMEOUT_S
            while not _answers(base):
                if proc.poll() is not None:
                    raise RuntimeError(f"postgrest exited with {proc.returncode}; see {log_path}")
                if time.monotonic() > deadline:
                    raise RuntimeError(f"postgrest not serving after {STARTUP_TIMEOUT_S}s; see {log_path}")
                time.sleep(1)
            yield base
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()
