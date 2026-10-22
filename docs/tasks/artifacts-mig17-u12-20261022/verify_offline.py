#!/usr/bin/env python3
"""Run real Rust checks in a disposable copy; never edit owner-controlled lib.rs."""
import argparse
import hashlib
import json
import pathlib
import shutil
import subprocess
import tempfile

parser=argparse.ArgumentParser()
parser.add_argument("--tests-only", action="store_true", help="Run actual tests; retain prior full-workspace fmt baseline separately")
args=parser.parse_args()

ROOT = pathlib.Path(__file__).resolve().parents[3]
if shutil.which("cargo") is None:
    print("NOT_RUN: cargo not installed; no installation attempted", flush=True)
    raise SystemExit(127)
print("Actual checkout:",subprocess.check_output(["git","rev-parse","HEAD"],cwd=ROOT,text=True).strip(),flush=True)
core=ROOT/"crates/muyon-core"
files=sorted((core/"src").rglob("*.rs"))+sorted((core/"tests").rglob("*.rs"))
bindings=[(str(f.relative_to(core)),hashlib.sha256(f.read_bytes()).hexdigest()) for f in files]
print("Actual Rust source manifest SHA256:",hashlib.sha256(json.dumps(bindings,separators=(",",":")).encode()).hexdigest(),flush=True)
with tempfile.TemporaryDirectory(prefix="muyon-artifact-verify-") as directory:
    copied = pathlib.Path(directory)
    tracked = subprocess.check_output(
        ["git", "ls-files", "-z"], cwd=ROOT
    ).decode().split("\0")
    for name in filter(None, tracked):
        source = ROOT / name
        if not source.is_file():
            continue
        destination = copied / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
    module = pathlib.Path("crates/muyon-core/src/artifacts")
    shutil.copytree(ROOT / module, copied / module, dirs_exist_ok=True)
    library = copied / "crates/muyon-core/src/lib.rs"
    text = library.read_text()
    for module_name in ("artifacts", "evidence"):
        if f"pub mod {module_name};" not in text:
            text += f"\npub mod {module_name};\n"
    library.write_text(text)
    commands = [
        ["cargo", "test", "--offline", "--manifest-path", "crates/Cargo.toml", "-p", "muyon-core", "artifacts"],
        ["cargo", "test", "--offline", "--manifest-path", "crates/Cargo.toml"],
        ["cargo", "fmt", "--manifest-path", "crates/Cargo.toml", "--all", "--", "--check"],
    ]
    if args.tests_only:
        commands=commands[:2]
    failures = []
    for command in commands:
        print("RUN", " ".join(command), flush=True)
        result = subprocess.run(command, cwd=copied)
        print("EXIT", result.returncode, flush=True)
        failures.append(result.returncode)
    raise SystemExit(1 if any(failures) else 0)
