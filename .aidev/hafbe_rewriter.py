#!/usr/bin/env python3
"""Run tests/rewriter through the postgrest-rewriter in front of PostgREST over the run's clone.

    hafbe_rewriter.py OUT_DIR

The rewriter is what Dockerfile.rewriter builds, run without docker: the runtime image
carries its base image's OpenResty (.aidev/runtime/Dockerfile), and its conf directory
gets the image's three files from this tree, docker/haf_block_explorer_nginx.conf.template
rendered as docker/rewriter_entrypoint.sh renders it, endpoints/rewrite_rules.conf and
endpoints/rpc_arguments.lua. Only the listen addresses and the upstream are changed, to
loopback ports and the PostgREST .aidev/postgrest.py starts.

Writes OUT_DIR/rewriter.xml (one junit case per test) and exits with pytest's status.
"""
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

from postgrest import serving

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
OPENRESTY = "/usr/local/openresty/nginx/sbin/nginx"
TEMPLATE_UPSTREAM = "http://block-explorer-postgrest:3000"
STARTUP_TIMEOUT_S = 30
WORKERS = os.environ.get("HAFBE_REWRITER_WORKERS", "4")


def _free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port: int = sock.getsockname()[1]
        return port


def _replace_once(text: str, old: str, new: str) -> str:
    if text.count(old) != 1:
        raise RuntimeError(f"the rewriter template no longer has exactly one {old!r}")
    return text.replace(old, new)


def render_config(conf_dir: str, postgrest: str, port: int, health_port: int) -> None:
    with open(os.path.join(ROOT, "docker", "haf_block_explorer_nginx.conf.template"), encoding="utf-8") as f:
        conf = f.read()
    # rewriter_entrypoint.sh's sed replaces every occurrence, the template's comment included
    conf = conf.replace("${REWRITE_LOG}", "rewrite_log on;")
    conf = _replace_once(conf, "listen 0.0.0.0:80 default_server;", f"listen 127.0.0.1:{port} default_server;")
    conf = _replace_once(conf, "listen 0.0.0.0:81;", f"listen 127.0.0.1:{health_port};")
    conf = _replace_once(conf, f"proxy_pass {TEMPLATE_UPSTREAM};", f"proxy_pass {postgrest};")
    with open(os.path.join(conf_dir, "nginx.conf"), "w", encoding="utf-8") as f:
        f.write(conf)
    for name in ("rewrite_rules.conf", "rpc_arguments.lua"):
        shutil.copy(os.path.join(ROOT, "endpoints", name), conf_dir)


def _answers(base: str) -> bool:
    try:
        with urllib.request.urlopen(base + "/version", timeout=5) as resp:
            status: int = resp.status
            return status == 200
    except (urllib.error.URLError, OSError):
        return False


def main(out: str) -> int:
    if not os.access(OPENRESTY, os.X_OK):
        print(f"{OPENRESTY} is missing: the runtime image carries the rewriter's OpenResty (.aidev/runtime/Dockerfile)")
        return 1
    os.makedirs(out, exist_ok=True)
    with serving(os.path.join(out, "postgrest-rewriter.log")) as postgrest, \
            tempfile.TemporaryDirectory() as prefix:
        os.makedirs(os.path.join(prefix, "conf"))
        os.makedirs(os.path.join(prefix, "logs"))
        port = _free_port()
        render_config(os.path.join(prefix, "conf"), postgrest, port, _free_port())
        base = f"http://127.0.0.1:{port}"
        with open(os.path.join(out, "rewriter.log"), "w") as log:
            proc = subprocess.Popen(
                [OPENRESTY, "-p", prefix, "-c", "conf/nginx.conf",
                 "-g", f"daemon off; pid {prefix}/nginx.pid;"],
                stdout=log, stderr=subprocess.STDOUT)
            try:
                deadline = time.monotonic() + STARTUP_TIMEOUT_S
                while not _answers(base):
                    if proc.poll() is not None:
                        print(f"the rewriter exited with {proc.returncode}; see {out}/rewriter.log")
                        return 1
                    if time.monotonic() > deadline:
                        print(f"the rewriter not serving after {STARTUP_TIMEOUT_S}s; see {out}/rewriter.log")
                        return 1
                    time.sleep(1)
                env = dict(os.environ, POSTGREST_URL=postgrest, REWRITER_URL=base)
                return subprocess.run(
                    [sys.executable, "-m", "pytest", "-n", WORKERS, "-p", "no:cacheprovider",
                     "--junitxml", os.path.abspath(os.path.join(out, "rewriter.xml")),
                     os.path.join(ROOT, "tests", "rewriter")],
                    cwd=os.path.join(ROOT, "tests", "rewriter"), env=env, check=False,
                ).returncode
            finally:
                proc.terminate()
                try:
                    proc.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    proc.kill()


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(f"usage: {sys.argv[0]} OUT_DIR")
    sys.exit(main(sys.argv[1]))
