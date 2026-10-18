#!/usr/bin/env python3
"""Verify the isolated deliverable at a fixed committed source; never overwrites logs."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
LAB = 'experiments/redesign/hy-memory-governance-lab'
FIXTURES = 'experiments/redesign/hy-memory-experiment-fixtures'
parser = argparse.ArgumentParser()
parser.add_argument('--sha', required=True)
parser.add_argument('--label', required=True)
a = parser.parse_args()
if not a.label.replace('-', '').replace('_', '').isalnum():
    raise SystemExit('label must be alphanumeric with dash/underscore')
def output(argv):
    return subprocess.check_output(argv, cwd=ROOT, text=True).strip()
sha = output(['git', 'rev-parse', 'HEAD'])
if sha != a.sha:
    raise SystemExit('HEAD differs from requested fixed SHA')
subprocess.run(['git', 'diff', '--exit-code', 'HEAD', '--', LAB, FIXTURES], cwd=ROOT, check=True)
if output(['git', 'ls-files', '--others', '--exclude-standard', '--', LAB, FIXTURES]):
    raise SystemExit('untracked source in deliverable')
evidence = Path(__file__).resolve().parent / 'evidence'
meta_path = evidence / (a.label + '.json')
with meta_path.open('x') as f:
    json.dump({'status':'running', 'sha':sha}, f)
env = dict(os.environ)
env['PATH'] = '/workspace/hy-tools/cargo/bin:' + env['PATH']
env['CARGO_HOME'] = '/workspace/hy-tools/cargo'
env['RUSTUP_HOME'] = '/workspace/hy-tools/rustup'
meta = {'sha':sha, 'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'lab_tree':output(['git', 'rev-parse', 'HEAD:' + LAB]),
        'source_sha256':{p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest()
            for p in output(['git', 'ls-files', '--', LAB, FIXTURES]).splitlines()},
        'runs':[]}
commands = [
    ['rustc', '--version'],
    ['cargo', '--version'],
    ['cargo', 'test', '--locked', '--offline', '--manifest-path', LAB + '/Cargo.toml'],
    ['python3', 'docs/tasks/hy-memory-governance-20261018/verify-fixtures.py'],
    ['git', 'diff', '--check'],
]
for i, command in enumerate(commands):
    log = evidence / f'{a.label}-{i}.log'
    with log.open('x') as f:
        result = subprocess.run(command, cwd=ROOT, env=env, stdout=f, stderr=subprocess.STDOUT)
    meta['runs'].append({'command':command, 'exit':result.returncode,
                         'log':log.name, 'sha256':hashlib.sha256(log.read_bytes()).hexdigest()})
    print(f'{result.returncode}: {command}: {log.name}', flush=True)
    meta_path.write_text(json.dumps(meta,indent=2)+'\n')
    if result.returncode:
        raise SystemExit(result.returncode)
meta['status'] = 'passed'
meta_path.write_text(json.dumps(meta,indent=2)+'\n')
