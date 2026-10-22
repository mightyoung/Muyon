#!/usr/bin/env python3
"""Compile two precise host inverses in retained private copies; no DUT mutation."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--evidence-dir', type=Path, required=True)
args = parser.parse_args()
args.evidence_dir.mkdir(parents=True, exist_ok=True)
source = Path(__file__).resolve().parent
if shutil.which('cargo') is None:
    raise SystemExit('NOT_RUN: preinstalled cargo required; no download is permitted')

mutations = [
    ('host_callback_request_identity',
     'if echoed_request != request_id', 'if false',
     'host_wrong_callback_identity_cannot_invoke_or_start_another_turn',
     '"completed"'),
    ('host_single_tool_admission',
     'if agent.state.counters.steps != 1 || self.invocations != 0', 'if false',
     'host_second_tool_proposal_never_dispatches_again',
     '"prepare"'),
]
results = []
for name, before, after, test, semantic_value in mutations:
    work = Path(tempfile.mkdtemp(prefix='core-host-inverse-'))
    crate = work / 'core'
    shutil.copytree(source, crate, ignore=shutil.ignore_patterns('target', '__pycache__'))
    path = crate / 'src' / 'host_session.rs'
    text = path.read_text()
    if text.count(before) != 1:
        raise SystemExit(f'{name}: expected exactly one mutation site')
    path.write_text(text.replace(before, after, 1))
    command = ['cargo', 'test', '--offline', '--locked', '--manifest-path', str(crate / 'Cargo.toml'),
               '--test', 'host', test, '--', '--exact', '--nocapture']
    try:
        run = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             text=True, timeout=120)
        output, returncode = run.stdout, run.returncode
    except subprocess.TimeoutExpired as exc:
        output = exc.stdout or ''
        if isinstance(output, bytes):
            output = output.decode(errors='replace')
        output += '\nINVALID_MUTANT_TIMEOUT\n'
        returncode = -1
    log = args.evidence_dir / f'{name}.log'
    log.write_text(output)
    compiled = 'Finished `test`' in output or 'Finished test' in output
    assertion = 'assertion `left == right` failed' in output and semantic_value in output
    killed = (returncode != 0 and compiled and assertion and 'test result: FAILED' in output
              and f'{test} ... FAILED' in output and 'INVALID_MUTANT_TIMEOUT' not in output)
    results.append(dict(name=name, test=test, compiled=compiled, semantic_assertion=assertion,
                        killed=killed, returncode=returncode, log=str(log), crate=str(crate)))
    print(f'{name}: {"KILLED" if killed else "INVALID_OR_SURVIVED"} compiled={compiled} assertion={assertion}', flush=True)
    for line in output.splitlines():
        if 'assertion ' in line or line.startswith(('  left:', ' right:', 'test result:')):
            print(line, flush=True)
(args.evidence_dir / 'summary.json').write_text(json.dumps(results, indent=2) + '\n')
if not all(item['killed'] for item in results):
    raise SystemExit(1)
