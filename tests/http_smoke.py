"""Boundary checks against the actual PHP front controller; no third-party packages."""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

root = Path(__file__).resolve().parents[1]
php = os.environ.get("PHP_BIN", "php")
# PHP_ARGS may be supplied as a JSON array for portable Windows extension loading.
php_args = json.loads(os.environ.get("PHP_ARGS", "[]"))
with tempfile.TemporaryDirectory(prefix="maurindesk-http-") as temp:
    env = dict(os.environ, APP_ENV="development", API_BASE_PATH="/v1",
               MAURINDESK_DB_PATH=str(Path(temp) / "api.sqlite"))
    subprocess.run([php, *php_args, "server/php/bin/migrate.php"], cwd=root, env=env, check=True)
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    base = f"http://127.0.0.1:{port}/v1"
    server = subprocess.Popen(
        [php, *php_args, "-S", f"127.0.0.1:{port}", "-t", "server/php/public", "server/php/public/index.php"],
        cwd=root, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(50):
            try:
                with urllib.request.urlopen(base + "/health", timeout=2) as response:
                    assert response.status == 200
                break
            except (OSError, urllib.error.URLError):
                time.sleep(0.1)
        else:
            raise RuntimeError("PHP server failed to start")
        def request(path, data=None):
            req = urllib.request.Request(base + path, data=data, headers={"Content-Type": "application/json"})
            try:
                with urllib.request.urlopen(req, timeout=5) as response:
                    return response.status, json.load(response), response.headers
            except urllib.error.HTTPError as error:
                return error.code, json.load(error), error.headers

        cases = [
            ("invalid-json", "/devices", b"{", 400),
            ("array-json", "/devices", b"[]", 400),
            ("oversized-body", "/devices", b"x" * 131073, 413),
            ("private-route", "/sessions/incoming", None, 401),
        ]
        for name, path, payload, expected in cases:
            status, body, headers = request(path, payload)
            assert status == expected, (name, status)
            assert "error" in body and "request_id" in body
            assert headers.get("Cache-Control") == "no-store"
            print("OK", name, status)
        print("HTTP boundary tests passed")
    finally:
        server.terminate()
        server.wait(timeout=10)
