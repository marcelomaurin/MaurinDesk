"""Build a credential-free Hostinger upload from the repository sources."""
from pathlib import Path
import argparse
import hashlib
import json
import zipfile

root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument("output", type=Path)
args = parser.parse_args()
source = root / "php"
files = [source / name for name in (".htaccess", ".env.sample", "bootstrap.php")]
for folder in ("api", "src", "migrations", "bin"):
    files.extend(sorted(path for path in (source / folder).rglob("*") if path.is_file()))
manifest = {"server": "https://maurinsoft.com.br/maurindesk/",
            "api": "https://maurinsoft.com.br/maurindesk/api/v1/",
            "initial_database_version": "0.1", "database_version": "0.2", "files": {}}
args.output.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(args.output, "w", zipfile.ZIP_DEFLATED) as archive:
    for path in files:
        relative = path.relative_to(source).as_posix()
        if path.name == ".env" or path.suffix in {".sqlite", ".db"}:
            raise ValueError("Private file in upload")
        data = path.read_bytes()
        archive.writestr("maurindesk/" + relative, data)
        manifest["files"][relative] = hashlib.sha256(data).hexdigest()
    archive.writestr("LEIA-ME-HOSTINGER.md", (source / "README.md").read_bytes())
    archive.writestr("manifest.json", json.dumps(manifest, indent=2).encode())
print(args.output.resolve())
