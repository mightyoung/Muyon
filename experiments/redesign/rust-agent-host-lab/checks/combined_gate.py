#!/usr/bin/env python3
"""Repository-owned exact-candidate gate; no batch3 external runner or evidence dependency."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
from source_identity import validate


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--expected-source', required=True)
    parser.add_argument('--component', choices=['core', 'plugin', 'host', 'native', 'http'], required=True)
    parser.add_argument('--evidence-dir', type=Path, required=True)
    parser.add_argument('--target-dir', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[4]
    evidence = args.evidence_dir.resolve()
    target = args.target_dir.resolve()
    if root == evidence or root in evidence.parents or root == target or root in target.parents:
        raise RuntimeError('evidence_and_target_must_be_outside_checkout')
    identity = validate(root, args.expected_source)
    if 'RUST_TEST_THREADS' in os.environ:
        raise RuntimeError('default_parallel_required')
    evidence.mkdir(parents=True, exist_ok=False)
    checks = Path(__file__).resolve().parent
    tracked = subprocess.check_output(['git', 'ls-files', '-z'], cwd=root).decode().split('\0')
    hashes = {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in tracked if name and (root/name).is_file()}
    (evidence/'source-manifest.json').write_text(json.dumps(dict(identity, files=hashes), indent=2)+'\n')
    env = dict(os.environ, EVIDENCE_DIR=str(evidence), CARGO_TARGET_DIR=str(target), CARGO_INCREMENTAL='0')
    command = ['bash', str(checks/'full.sh'), args.component]
    if args.component == 'native':
        command = [sys.executable, '-B', str(checks/'native_mutations.py'), '--evidence-dir', str(evidence/'native')]
    elif args.component == 'http':
        command = [sys.executable, '-B', str(checks/'http_batch_inverses.py'), '--source-root', str(root),
                   '--expected-source', args.expected_source, '--evidence-dir', str(evidence/'http'), '--work-dir', str(target/'http-work')]
    status = subprocess.call(command, cwd=root, env=env)
    unchanged = all((root/name).is_file() and hashlib.sha256((root/name).read_bytes()).hexdigest() == digest for name, digest in hashes.items())
    unchanged = unchanged and validate(root, args.expected_source) == identity
    binary_integrity = True
    manifest = evidence/'binary-sha256.txt'
    if manifest.is_file():
        with (evidence/'binary-integrity.log').open('w') as log:
            binary_integrity = subprocess.call(['sha256sum', '--check', str(manifest)], cwd=root, stdout=log, stderr=subprocess.STDOUT) == 0
    result = dict(identity, component=args.component, command=command, exit_code=status,
                  source_inputs_unchanged=unchanged, baseline_binaries_unchanged=binary_integrity,
                  accepted=status == 0 and unchanged and binary_integrity)
    (evidence/'gate-verdict.json').write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(result))
    return 0 if result['accepted'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
