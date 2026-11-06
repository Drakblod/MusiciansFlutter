"""Run the complete emulator suite without ambient credentials or providers."""

import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time


ROOT = Path(__file__).resolve().parents[2]
PROJECT = "demo-musicians-test"
FAKE_KEY = "EMULATOR_ONLY_FAKE_KEY_DO_NOT_USE"
SECRET = ROOT / "firebase_functions" / ".secret.local"
LOCAL_ENV = ROOT / "firebase_functions" / ".env.local"
GUARD = ROOT / "firebase_functions" / "test" / "emulator_isolation_guard.js"
LOG = ROOT / "build" / "emulator-isolation-gate.log"
RESULT = ROOT / "build" / "emulator-isolation-results.json"


def git(*args):
    return subprocess.check_output(
        ["git", "-c", "core.fsmonitor=false", *args], cwd=ROOT,
        text=True, stderr=subprocess.DEVNULL).strip()


def preflight():
    if not PROJECT.startswith("demo-"):
        raise RuntimeError("Only demo projects are permitted")
    if not GUARD.is_file():
        raise RuntimeError("Network guard is missing")
    if subprocess.run(["git", "check-ignore", "-q", "firebase_functions/.secret.local"],
                      cwd=ROOT, check=False).returncode != 0:
        raise RuntimeError(".secret.local is not ignored by Git")
    if subprocess.run(["git", "check-ignore", "-q", "firebase_functions/.env.local"],
                      cwd=ROOT, check=False).returncode != 0:
        raise RuntimeError(".env.local is not ignored by Git")
    if git("diff", "--cached", "--name-only"):
        raise RuntimeError("Staging area must remain empty")
    config = json.loads((ROOT / "firebase.json").read_text(encoding="utf-8"))
    expected = {"auth": 9099, "database": 9000, "functions": 5001}
    for name, port in expected.items():
        if config["emulators"][name]["port"] != port:
            raise RuntimeError(f"Unexpected {name} emulator port")
        with socket.socket() as sock:
            sock.settimeout(0.3)
            if sock.connect_ex(("127.0.0.1", port)) == 0:
                raise RuntimeError(f"Port {port} already has a listener")
    script = json.loads((ROOT / "firebase_functions" / "package.json").read_text(
        encoding="utf-8"))["scripts"]["test:emulator"]
    if "test/emulator_isolation.test.js" not in script:
        raise RuntimeError("Isolation assertion is not registered in test:emulator")
    return sorted(set(re.findall(r"test/[\w]+\.test\.js", script)))


def isolated_env(temp):
    env = os.environ.copy()
    for key in ("GOOGLE_APPLICATION_CREDENTIALS", "FIREBASE_TOKEN",
                "FIREBASE_DATABASE_URL", "FIREBASE_CONFIG", "NODE_OPTIONS",
                "GOOGLE_API_KEY", "GOOGLE_PLACES_API_KEY"):
        env.pop(key, None)
    for name in ("appdata", "home", "gcloud", "xdg"):
        (temp / name).mkdir()
    source_jar = Path.home() / ".cache" / "firebase" / "emulators" / \
        "firebase-database-emulator-v4.11.2.jar"
    if not source_jar.is_file():
        raise RuntimeError("The preinstalled local Database Emulator is unavailable")
    configstore = temp / "xdg" / "configstore"
    configstore.mkdir()
    (configstore / "firebase-tools.json").write_text(json.dumps({
        "motd": {"fetched": int(time.time() * 1000)}}), encoding="utf-8")
    env.update({
        "APPDATA": str(temp / "appdata"),
        "HOME": str(temp / "home"),
        "USERPROFILE": str(temp / "home"),
        "CLOUDSDK_CONFIG": str(temp / "gcloud"),
        "XDG_CONFIG_HOME": str(temp / "xdg"),
        "FIREBASE_EMULATORS_PATH": str(source_jar.parent),
        "METADATA_SERVER_DETECTION": "none",
        "GCLOUD_PROJECT": PROJECT,
        "GOOGLE_CLOUD_PROJECT": PROJECT,
        "FIREBASE_PROJECT_ID": PROJECT,
        "FIREBASE_DATABASE_EMULATOR_HOST": "127.0.0.1:9000",
        "FIREBASE_AUTH_EMULATOR_HOST": "127.0.0.1:9099",
        "FUNCTIONS_EMULATOR_HOST": "127.0.0.1:5001",
        "EMULATOR_ISOLATION_GATE": "true",
        "EMULATOR_ISOLATION_TEMP": str(temp),
        "EMULATOR_ISOLATION_ATTEMPTS": str(temp / "attempts.jsonl"),
        "FUNCTIONS_DISCOVERY_TIMEOUT": "120",
        "CI": "true",
        "NO_UPDATE_NOTIFIER": "1",
        "npm_config_offline": "true",
        "NPM_CONFIG_OFFLINE": "true",
        "NODE_OPTIONS": f"--require={GUARD}",
        "LIVEKIT_API_KEY": "EMULATOR_ONLY_FAKE_LIVEKIT_KEY",
        "LIVEKIT_API_SECRET": "EMULATOR_ONLY_FAKE_LIVEKIT_SECRET",
        "LIVEKIT_URL": "ws://127.0.0.1:65535",
    })
    adc = temp / "appdata" / "gcloud" / "application_default_credentials.json"
    if adc.exists() or env.get("GOOGLE_APPLICATION_CREDENTIALS"):
        raise RuntimeError("Ambient ADC is still available")
    return env


def verify_guard(env, temp):
    node = shutil.which("node")
    if not node:
        raise RuntimeError("Node.js is unavailable")
    check = subprocess.run([node, "-e",
        "if(globalThis.__EMULATOR_ISOLATION_GUARD_ACTIVE__!==true)process.exit(2)"],
        env=env, cwd=ROOT, capture_output=True, text=True, check=False)
    if check.returncode:
        raise RuntimeError("Network guard failed its isolated preload")
    probe = env.copy()
    probe["EMULATOR_ISOLATION_ATTEMPTS"] = str(temp / "guard-probe.jsonl")
    check = subprocess.run([node, "-e",
        "fetch('https://example.invalid/').then(()=>process.exit(2))"
        ".catch(()=>process.exit(0))"],
        env=probe, cwd=ROOT, capture_output=True, text=True, check=False)
    if check.returncode or not (temp / "guard-probe.jsonl").is_file():
        raise RuntimeError("Network guard did not reject an external destination")
    (temp / "guard-probe.jsonl").unlink()


def summarize(expected, run_code, temp):
    output = LOG.read_text(encoding="utf-8", errors="replace")
    attempts = temp / "attempts.jsonl"
    if attempts.exists() and attempts.stat().st_size:
        raise RuntimeError("An external network destination was attempted")
    if "Trying to access secret" in output or "secretmanager.googleapis.com" in output:
        raise RuntimeError("Functions Emulator attempted Cloud Secret Manager")
    if output.count("ISOLATION_GUARD_ACTIVE") < 3:
        raise RuntimeError("The guard did not load in all required Node processes")
    if any(value in output for value in (FAKE_KEY,
            "EMULATOR_ONLY_FAKE_LIVEKIT_KEY",
            "EMULATOR_ONLY_FAKE_LIVEKIT_SECRET")):
        raise RuntimeError("Fake provider credential appeared in logs")
    if not RESULT.is_file():
        raise RuntimeError("Mocha did not write its complete result file")
    data = json.loads(RESULT.read_text(encoding="utf-8"))
    actual = {"test/" + Path(test["file"]).name for test in data["tests"]}
    if actual != set(expected):
        raise RuntimeError(f"Test-file mismatch: expected {len(expected)}, ran {len(actual)}")
    per_file = {}
    passed = {id(test) for test in data["passes"]}
    failed = {id(test) for test in data["failures"]}
    pending = {id(test) for test in data["pending"]}
    # JSON reporter serializes each category separately, so classify by stable
    # full title and file instead of Python object identity.
    def key(test):
        return (test["file"], test["fullTitle"])
    passed = {key(test) for test in data["passes"]}
    failed = {key(test) for test in data["failures"]}
    pending = {key(test) for test in data["pending"]}
    for test in data["tests"]:
        file = "test/" + Path(test["file"]).name
        counts = per_file.setdefault(file, {"passed": 0, "failed": 0, "skipped": 0})
        category = "passed" if key(test) in passed else "failed" if key(test) in failed else "skipped"
        counts[category] += 1
    totals = {name: sum(row[name] for row in per_file.values())
              for name in ("passed", "failed", "skipped")}
    summary = {"exitCode": run_code, "totals": totals, "perFile": per_file,
               "guardProcesses": output.count("ISOLATION_GUARD_ACTIVE"),
               "externalAttempts": 0, "secretManagerAttempts": 0,
               "expectedFiles": len(expected), "actualFiles": len(actual)}
    (ROOT / "build" / "emulator-isolation-summary.json").write_text(
        json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))
    if run_code or totals["failed"] or totals["skipped"]:
        raise RuntimeError("Complete emulator suite did not pass")


def main():
    expected = preflight()
    ROOT.joinpath("build").mkdir(exist_ok=True)
    previous = SECRET.read_bytes() if SECRET.exists() else None
    previous_env = LOCAL_ENV.read_bytes() if LOCAL_ENV.exists() else None
    with tempfile.TemporaryDirectory(prefix="emulator-isolation-", dir=ROOT / "build") as name:
        temp = Path(name)
        try:
            env = isolated_env(temp)
            verify_guard(env, temp)
            SECRET.write_text(f"GOOGLE_PLACES_API_KEY={FAKE_KEY}\n", encoding="utf-8")
            LOCAL_ENV.write_text(
                "LIVEKIT_API_KEY=EMULATOR_ONLY_FAKE_LIVEKIT_KEY\n"
                "LIVEKIT_API_SECRET=EMULATOR_ONLY_FAKE_LIVEKIT_SECRET\n"
                "LIVEKIT_URL=ws://127.0.0.1:65535\n", encoding="utf-8")
            if not git("check-ignore", "firebase_functions/.secret.local"):
                raise RuntimeError("Temporary secret lost its Git ignore rule")
            if not git("check-ignore", "firebase_functions/.env.local"):
                raise RuntimeError("Temporary provider override lost its Git ignore rule")
            RESULT.unlink(missing_ok=True)
            firebase_cli = shutil.which("firebase.cmd") or shutil.which("firebase")
            if not firebase_cli:
                raise RuntimeError("Firebase CLI is unavailable")
            command = [firebase_cli, "emulators:exec", "--project", PROJECT,
                       "--only", "auth,database,functions",
                       "npm --prefix firebase_functions run test:emulator -- "
                       "--reporter json --reporter-option output=../build/emulator-isolation-results.json"]
            print("Running isolated demo Auth, Database and Functions emulators")
            with LOG.open("w", encoding="utf-8") as log:
                outcome = subprocess.run(command, cwd=ROOT, env=env, stdout=log,
                                         stderr=subprocess.STDOUT, check=False)
            summarize(expected, outcome.returncode, temp)
        finally:
            if previous is None:
                SECRET.unlink(missing_ok=True)
            else:
                SECRET.write_bytes(previous)
            if previous_env is None:
                LOCAL_ENV.unlink(missing_ok=True)
            else:
                LOCAL_ENV.write_bytes(previous_env)
            status = git("status", "--short")
            if ".secret.local" in status or ".env.local" in status:
                raise RuntimeError("Temporary provider configuration appears in Git status")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"ISOLATED_EMULATOR_RUN_FAILED: {error}", file=sys.stderr)
        sys.exit(1)
