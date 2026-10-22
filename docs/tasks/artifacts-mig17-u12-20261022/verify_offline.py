#!/usr/bin/env python3
"""Run real Rust checks in a disposable copy; never edit owner-controlled lib.rs."""
import pathlib
import shutil
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[3]
if shutil.which("cargo") is None:
    print("NOT_RUN: cargo not installed; no installation attempted", flush=True)
    raise SystemExit(127)
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
    if "pub mod artifacts;" not in text:
        library.write_text(text + "\npub mod artifacts;\n")
    commands = [
        ["cargo", "test", "--offline", "--manifest-path", "crates/Cargo.toml", "-p", "muyon-core", "artifacts"],
        ["cargo", "test", "--offline", "--manifest-path", "crates/Cargo.toml"],
        ["cargo", "fmt", "--manifest-path", "crates/Cargo.toml", "--all", "--", "--check"],
    ]
    failures = []
    for command in commands:
        print("RUN", " ".join(command), flush=True)
        result = subprocess.run(command, cwd=copied)
        print("EXIT", result.returncode, flush=True)
        failures.append(result.returncode)
    raise SystemExit(1 if any(failures) else 0)
