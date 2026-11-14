"""Two native workers against the actual PHP API, in an isolated workspace fixture."""
import hashlib
import json
import os
from pathlib import Path
import socket
import subprocess
import time
import urllib.request
import uuid

root = Path(__file__).resolve().parents[1]
fixture = root / "build" / ("file-service-" + uuid.uuid4().hex)
fixture.mkdir(parents=True)
source, destination, download = [fixture / name for name in ("Source", "Remote", "Download")]
for folder in (source, destination, download):
    folder.mkdir()
(source / "Arquivo.txt").write_text("Texto Unicode: Olá 漢字 😀", encoding="utf-8")
(source / "Pasta" / "Pasta vazia").mkdir(parents=True)
(source / "Pasta" / "ação.bin").write_bytes(os.urandom(1024 * 1024 + 67))
php = os.environ.get("PHP_BIN", "php")
args = json.loads(os.environ.get("PHP_ARGS", "[]"))
with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
base = f"http://127.0.0.1:{port}/maurindesk/api/v1"
env = dict(os.environ, APP_ENV="development", API_BASE_PATH="/maurindesk/api/v1", DB_DRIVER="sqlite",
           MAURINDESK_ENV_FILE=str(fixture / "unused.env"), MAURINDESK_DB_PATH=str(fixture / "api.sqlite"))
log = (fixture / "php.log").open("w")
server = subprocess.Popen([php, *args, "-S", f"127.0.0.1:{port}", "-t", "server/api", "server/api/index.php"], cwd=root, env=env, stdout=log, stderr=log)
def request(route, data=None, token=None):
    headers = {"Content-Type": "application/json", "Idempotency-Key": str(uuid.uuid4())}
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(base + route, data=None if data is None else json.dumps(data).encode(), headers=headers)
    with urllib.request.urlopen(req, timeout=10) as response:
        return json.load(response)["data"]
try:
    for _ in range(50):
        try:
            request("/health")
            break
        except OSError:
            time.sleep(.1)
    def device(name):
        return request("/devices", {"registration_id": str(uuid.uuid4()), "registration_secret": uuid.uuid4().hex * 2,
            "display_name": name, "platform": "test", "app_version": "0.6.7"})
    host, controller = device("Native host"), device("Native controller")
    config = dict(url=base, host_token=host["device_token"], controller_token=controller["device_token"], host_key=host["public_key"],
                  source=str(source), destination=str(destination), download=str(download), cache=str(fixture / "Cache"), preview=str(fixture / "preview.png"))
    (fixture / "config.json").write_text(json.dumps(config), encoding="utf-8")
    result = subprocess.run([str(root / "build" / "file_service_probe.exe"), str(fixture / "config.json")], cwd=root, capture_output=True, timeout=120)
    (fixture / "native.log").write_bytes(result.stdout)
    print(result.stdout.decode(errors="replace").splitlines()[-1] if result.stdout else "Native test finished")
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors="replace"))
    for target in (destination, download):
        for relative in (Path("Arquivo.txt"), Path("Pasta/ação.bin")):
            assert hashlib.sha256((target / relative).read_bytes()).digest() == hashlib.sha256((source / relative).read_bytes()).digest(), str(target / relative)
        assert (target / "Pasta/Pasta vazia").is_dir()
    print("PASS: upload and download preserve exact bytes, Unicode filenames and empty folders in chosen final destinations")
    print("Preview:", fixture / "preview.png")
finally:
    server.terminate()
    server.wait(timeout=10)
    log.close()
    # Remove only the disposable credentials, retain fixtures and test evidence.
    if (fixture / "config.json").exists():
        (fixture / "config.json").unlink()
