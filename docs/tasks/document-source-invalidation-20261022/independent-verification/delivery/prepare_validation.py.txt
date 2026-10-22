#!/usr/bin/env python3
"""Prepare a disposable exact-source tree, never install tools or run an engine."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

BASE = "b4940ddc1600acced5e268053450b48395df93f6"
DEPENDENCY = "0e85c6e98c4e32efc8008092e480626f342a701d"
TASK = Path(__file__).resolve().parent
REPO = TASK.parents[2]


def git(*args, cwd=REPO):
    return subprocess.check_output(["git", *args], cwd=cwd)


def prepare(destination):
    destination = destination.absolute()
    if not any(destination.is_relative_to(root) for root in (Path("/tmp"), Path("/workspace"))):
        raise SystemExit("Disposable destination must be inside /tmp or /workspace")
    if destination.exists():
        raise SystemExit("Destination already exists; inspect state instead of overwriting/retrying")
    git("worktree", "add", "--detach", str(destination), BASE)
    files = []
    # Exact dependency bytes in a new disposable tree, not edits to owner source.
    tree = git("ls-tree", "-r", "-z", DEPENDENCY, "--", "crates/muyon-core/src/artifacts", "crates/muyon-core/src/evidence")
    for record in tree.split(b"\0"):
        if not record:
            continue
        header, name = record.split(b"\t", 1)
        mode, kind, object_id = header.split()
        if mode not in (b"100644", b"100755") or kind != b"blob":
            raise SystemExit("Unexpected nonregular dependency source")
        relative = name.decode()
        path = destination / relative
        if path.is_symlink():
            raise SystemExit("Unexpected dependency symlink")
        data = git("cat-file", "blob", object_id.decode())
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        files.append({"path": relative, "sha256": hashlib.sha256(data).hexdigest()})
    manifest = json.loads((TASK / "patch-manifest.json").read_text())
    patch = TASK / "CORE-SOURCE-INVALIDATION.patch"
    if hashlib.sha256(patch.read_bytes()).hexdigest() != manifest["core_patch_sha256"]:
        raise SystemExit("Core patch hash mismatch")
    for name in ("CORE-SOURCE-INVALIDATION.patch", "UNAPPLIED-B-HARNESS-DEPENDENCIES.patch"):
        git("apply", "--check", str(TASK / name), cwd=destination)
        git("apply", str(TASK / name), cwd=destination)
    for expected in manifest["patched_files"]:
        digest = hashlib.sha256((destination / expected["path"]).read_bytes()).hexdigest()
        if digest != expected["sha256"]:
            raise SystemExit("Patched result hash mismatch: " + expected["path"])
        files.append(expected)
    for relative in ("crates/muyon-core/src/bin/business_worker.rs", "crates/muyon-core/tests/group_runtime_store.rs", "crates/muyon-core/src/lib.rs"):
        files.append({"path": relative, "sha256": hashlib.sha256((destination / relative).read_bytes()).hexdigest()})
    result = {"base": BASE, "dependency": DEPENDENCY, "core_patch_sha256": manifest["core_patch_sha256"],
              "harness_patch_sha256": hashlib.sha256((TASK / "UNAPPLIED-B-HARNESS-DEPENDENCIES.patch").read_bytes()).hexdigest(),
              "destination": str(destination), "lib_rs_unchanged_from_base": git("show", BASE + ":crates/muyon-core/src/lib.rs") == (destination / "crates/muyon-core/src/lib.rs").read_bytes(),
              "note": "Prepared only; no cargo, formatter, engine, network or notification executed", "files": files}
    (destination / "SOURCE-INVALIDATION-MANIFEST.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("destination", type=Path)
    prepare(parser.parse_args().destination)
