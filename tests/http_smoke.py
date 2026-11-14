"""Boundary checks against the actual PHP front controller; no third-party packages."""
import json
import base64
import hashlib
import uuid
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
    env = dict(os.environ, APP_ENV="development", API_BASE_PATH="/maurindesk/api/v1",
               DB_DRIVER="sqlite", MAURINDESK_ENV_FILE=str(Path(temp) / "unused.env"),
               MAURINDESK_DB_PATH=str(Path(temp) / "api.sqlite"))
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    base = f"http://127.0.0.1:{port}/maurindesk/api/v1"
    server = subprocess.Popen(
        [php, *php_args, "-S", f"127.0.0.1:{port}", "-t", "server/api", "server/api/index.php"],
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
        # The first health call must create the database and its tables automatically.
        def request(path, data=None, headers=None, method=None):
            url = path if path.startswith("http://") else base + path
            req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json", **(headers or {})}, method=method)
            try:
                with urllib.request.urlopen(req, timeout=5) as response:
                    return response.status, json.load(response), response.headers
            except urllib.error.HTTPError as error:
                return error.code, json.load(error), error.headers

        cases = [
            ("invalid-json", "/devices", b"{", 400),
            ("array-json", "/devices", b"[]", 400),
            ("oversized-body", "/devices", b"x" * 1048577, 413),
            ("private-route", "/sessions/incoming", None, 401),
        ]
        for name, path, payload, expected in cases:
            status, body, headers = request(path, payload)
            assert status == expected, (name, status)
            assert "error" in body and "request_id" in body
            assert headers.get("Cache-Control") == "no-store"
            print("OK", name, status)
        status, body, _ = request(base.rsplit("/v1", 1)[0] + "/")
        assert status == 200 and body["data"]["version"] == "0.8"
        print("OK server root health and initial version")
        status, body, _ = request("/devices", json.dumps({
            "registration_id": "12345678-1234-4234-8234-123456789abc",
            "registration_secret": "a" * 64, "display_name": "HTTP host",
            "platform": "test", "app_version": "0.1"}).encode())
        assert status == 201, body
        device = body["data"]
        status, body, _ = request("/devices/endpoint", b'{"port":49152,"transport":"tcp"}', {
            "Authorization": "Bearer " + device["device_token"],
            "Idempotency-Key": "12345678-1234-4234-8234-123456789abd",
            "X-Forwarded-For": "203.0.113.99"})
        assert status == 200 and body["data"]["observed_ip"] == "127.0.0.1", body
        print("OK source IP cannot be spoofed by forwarded header")
        auth = {"Authorization": "Bearer " + device["device_token"],
                "Idempotency-Key": "12345678-1234-4234-8234-123456789abe"}
        status, body, _ = request("/desktop/preferences", b'{"view_mode":"list","theme":"dark"}', auth, "PATCH")
        assert status == 200 and body["data"]["view_mode"] == "list", body
        print("OK desktop preferences via PATCH")
        status, body, _ = request("/contacts", b'{"remote_key":"0123456789","alias":"Trabalho","is_favorite":true}', auth)
        assert status == 200 and body["data"]["is_favorite"] is True, body
        print("OK favorite card saved via HTTP")
        status, body, _ = request("/desktop", headers=auth)
        assert status == 200 and body["data"]["favorites"][0]["alias"] == "Trabalho", body
        assert body["data"]["preferences"]["theme"] == "dark", body
        print("OK desktop dashboard loads saved card and preferences")
        status, body, _ = request("/devices", json.dumps({
            "registration_id": str(uuid.uuid4()), "registration_secret": "b" * 64,
            "display_name": "HTTP controller", "platform": "test", "app_version": "0.6.5"}).encode())
        assert status == 201, body
        controller = body["data"]
        def authenticated(path, who, data=None, method=None):
            headers = {"Authorization": "Bearer " + who["device_token"], "Idempotency-Key": str(uuid.uuid4())}
            return request(path, None if data is None else json.dumps(data).encode(), headers, method)
        status, body, _ = authenticated("/sessions", controller, {
            "target_key": device["public_key"], "requested_permissions": ["screen.view", "clipboard.sync"]})
        assert status == 201, body
        sid = body["data"]["id"]
        status, body, _ = authenticated(f"/sessions/{sid}/decision", device, {
            "decision": "accept", "granted_permissions": ["screen.view", "clipboard.sync"]})
        assert status == 200, body
        raw = "Olá — Unicode 漢字 😀".encode()
        clip = f"/sessions/{sid}/clipboard"
        status, body, _ = authenticated(clip, controller, {"kind": "text", "total_bytes": len(raw), "checksum": hashlib.sha1(raw).hexdigest()})
        assert status == 200, body
        transfer = body["data"]["id"]
        status, body, _ = authenticated(f"{clip}/{transfer}/0", controller, {"data": base64.b64encode(raw).decode()})
        assert status == 200, body
        status, body, _ = authenticated(f"{clip}/{transfer}", controller, {})
        assert status == 200 and body["data"]["status"] == "ready", body
        status, body, _ = authenticated(f"{clip}/{transfer}/0", device)
        assert status == 200 and base64.b64decode(body["data"]["data"]) == raw, body
        status, body, _ = authenticated(f"{clip}/{transfer}", device, {"received": True})
        assert status == 200 and body["data"]["status"] == "received", body
        status, body, _ = authenticated(f"{clip}/{transfer}", controller)
        assert status == 200 and body["data"]["status"] == "received", body
        print("OK clipboard consent, chunk upload, commit and download via HTTP")
        print("HTTP boundary tests passed")
    finally:
        server.terminate()
        server.wait(timeout=10)
