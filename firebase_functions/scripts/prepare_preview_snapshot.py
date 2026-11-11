"""Build and verify the 2.80.3 Notification V2 snapshot from a clean Git checkout.

Put Node 22.13.1 on PATH and pass the npm CLI JavaScript entry point:
  python firebase_functions/scripts/prepare_preview_snapshot.py build/notification-cutover --npm-cli PATH

The script copies local files only. The deployment-plan.json it produces lists
only the reviewed notification cutover targets.
"""

import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile


ROOT = Path(__file__).resolve().parents[2]
MANIFEST = Path("scripts/notification_2_80_3_manifest.json")
DISCOVER = """
const path = require('node:path');
const deny = () => { throw new Error('Offline discovery forbids network access'); };
require('node:net').Socket.prototype.connect = deny;
require('node:tls').connect = deny;
require('node:http').request = deny;
require('node:https').request = deny;
require('node:dns').lookup = deny;
globalThis.fetch = deny;
const sdk = require.resolve('firebase-functions');
if (!sdk.startsWith(path.join(process.cwd(), 'node_modules') + path.sep)) {
  throw new Error('firebase-functions must resolve inside the snapshot');
}
const functions = require(path.resolve('index.js'));
const endpoints = Object.fromEntries(Object.entries(functions)
  .filter(([, fn]) => fn.__endpoint)
  .map(([name, fn]) => [name, fn.__endpoint]));
console.log(JSON.stringify(endpoints));
"""


def git(*args):
    return subprocess.check_output(
        ["git", "-c", "core.fsmonitor=false", *args], cwd=ROOT
    )


def install_dependencies(node, npm_cli, source, env):
    # Separate the install from local npm config and caches. The lockfile
    # supplies the versions and integrity checks for the runtime dependencies.
    with tempfile.TemporaryDirectory(dir=source.parent.parent) as scratch:
        config = Path(scratch)
        for name in ("user.npmrc", "global.npmrc"):
            (config / name).touch()
        subprocess.run(
            [
                node, npm_cli, "ci", "--omit=dev", "--ignore-scripts",
                "--no-audit", "--no-fund", "--registry=https://registry.npmjs.org",
                f"--userconfig={config / 'user.npmrc'}",
                f"--globalconfig={config / 'global.npmrc'}",
                f"--cache={config / 'cache'}",
            ],
            cwd=source, env=env, check=True,
        )


def descriptor_sha256(endpoints):
    canonical = json.dumps(endpoints, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode()).hexdigest()


def verify_snapshot(output, node, npm_cli):
    source = output / "firebase_functions"
    if any(p.name.startswith((".env", ".secret")) for p in source.rglob("*")):
        raise SystemExit("Unexpected environment or secret file in the Git archive")
    env = {
        key: value for key, value in os.environ.items()
        if not key.upper().startswith(("NPM_CONFIG_", "FIREBASE_", "LIVEKIT_"))
        and key.upper() not in {
            "NODE_PATH", "NODE_OPTIONS", "FUNCTIONS_EMULATOR",
            "GOOGLE_APPLICATION_CREDENTIALS", "GOOGLE_PLACES_API_KEY", "NODE_ENV",
        }
    }
    install_dependencies(node, npm_cli, source, env)

    env["GCLOUD_PROJECT"] = "musiciansapp-35f70"
    env["GOOGLE_CLOUD_PROJECT"] = "musiciansapp-35f70"
    env["FIREBASE_CONFIG"] = json.dumps({
        "projectId": "musiciansapp-35f70",
        "databaseURL": "https://musiciansapp-35f70-default-rtdb.europe-west1.firebasedatabase.app",
    })
    endpoints = json.loads(subprocess.check_output(
        [node, "--no-global-search-paths", "-"], input=DISCOVER.encode(), cwd=source, env=env,
    ))
    manifest = json.loads((source / MANIFEST).read_text(encoding="utf-8"))
    new_callables = set(manifest["cutover"]["newCallables"])
    baseline = {name: descriptor for name, descriptor in endpoints.items()
                if name not in new_callables}
    if (len(endpoints) != 58 or sorted(endpoints) != manifest["endpoints"]
            or any(endpoint.get("region") != [manifest["region"]]
                   for endpoint in endpoints.values())
            or descriptor_sha256(endpoints) != manifest["descriptorSha256"]
            or len(baseline) != 54
            or descriptor_sha256(baseline) != manifest["baselineDescriptorSha256"]):
        raise SystemExit("Offline Functions discovery differs from the reviewed 58-endpoint manifest")
    targets = [name for group in manifest["cutover"].values() for name in group]
    excluded = set(manifest["excluded"])
    if (excluded != {"checkEventReminders"} or not excluded <= endpoints.keys()
            or len(targets) != 22 or len(set(targets)) != len(targets)
            or not set(targets) <= endpoints.keys() or excluded.intersection(targets)):
        raise SystemExit("Controlled notification cutover targets differ from the reviewed scope")
    (output / "deployment-plan.json").write_text(json.dumps(targets, indent=2), encoding="utf-8")
    print(f"Verified 58 endpoints offline ({descriptor_sha256(endpoints)}); prepared 22 notification cutover targets.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--npm-cli", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    npm_cli = args.npm_cli.resolve(strict=True)
    node = shutil.which("node")
    if not node or subprocess.check_output([node, "--version"]).strip() != b"v22.13.1":
        parser.error("Node 22.13.1 must be on PATH")
    if not output.is_relative_to(ROOT / "build") or output == ROOT / "build" or output.exists():
        parser.error("output must be a new directory under the checkout's ignored build/")
    if git("status", "--porcelain"):
        parser.error("the checkout must be clean")

    archive = git(
        "archive", "HEAD", ".firebaserc", "firebase.json", "firebase_functions",
        "database.rules.json", "storage.rules",
    )
    output.mkdir(parents=True, exist_ok=False)
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        tar.extractall(output, filter="data")
    verify_snapshot(output, node, npm_cli)


if __name__ == "__main__":
    main()
