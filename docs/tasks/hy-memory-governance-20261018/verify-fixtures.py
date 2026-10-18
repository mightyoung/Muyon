#!/usr/bin/env python3
"""Replay fixture checks without changing the checked-out fixture files."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / 'experiments/redesign/hy-memory-experiment-fixtures'
records = []
with tempfile.TemporaryDirectory(prefix='hy-fixture-review-') as td:
    clone = Path(td) / 'fixtures'
    shutil.copytree(SOURCE, clone)
    def run(args, expected):
        p = subprocess.run(args, cwd=ROOT, text=True, capture_output=True)
        records.append(dict(command=args, exit=p.returncode, stdout=p.stdout, stderr=p.stderr,
                            expected=expected))
        assert (p.returncode == 0) == (expected == 'PASS'), records[-1]
    run(['python3', str(clone / 'validate_fixtures.py')], 'PASS')
    before = {n: (clone / n).read_bytes() for n in ['writer.json', 'diff-index.json']}
    run(['python3', str(clone / 'build_fixtures.py')], 'PASS')
    assert all((clone / n).read_bytes() == data for n, data in before.items())
    print('PASS deterministic regeneration')
    def mutate(name, change):
        doc = json.loads(before[name]); change(doc)
        (clone / name).write_text(json.dumps(doc))
        run(['python3', str(clone / 'validate_fixtures.py')], 'REJECT')
        (clone / name).write_bytes(before[name])
    mutate('diff-index.json', lambda d: next(c for c in d['cases'] if c['condition']=='missing_base').update(expected_status='EMPTY'))
    mutate('diff-index.json', lambda d: d['content_objects'][0].update(content='CORRUPT synthetic object'))
    mutate('diff-index.json', lambda d: d['sidecar_candidate_refs'][0].update(target_revision='revision-synthetic-wrong'))
    mutate('writer.json', lambda d: next(c for c in d['cases'] if c['host_condition']=='same_intent_same_payload').update(expected_business_writes=1))
    print('PASS four invalid-fixture mutations rejected (fixture consistency only; DUT_runs=0)')
print(json.dumps({'source_sha256': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(SOURCE.iterdir()) if p.is_file()}, 'runs':records}, indent=2))
