"""Offline integrity check for the immutable Library intake; no product execution."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent
manifest = json.loads((root / 'sources.json').read_text())
assert len(manifest['files']) == 17
assert len({x['library_file_id'] for x in manifest['files']}) == 17
for item in manifest['files']:
    data = (root / item['path']).read_bytes()
    assert len(data) == item['size_bytes'], item['path']
    assert hashlib.sha256(data).hexdigest() == item['sha256'], item['path']
    assert item['complete'] is True
images = sorted((root / 'ui-v1.0').glob('*.png'))
assert len(images) == 9
assert [x.name[:2] for x in images] == [f'{i:02d}' for i in range(1, 10)]
pr = json.loads((root / 'evidence/pr100.json').read_text())
assert pr['headRefOid'] == manifest['candidate_sha']
for run in json.loads((root / 'evidence/candidate-runs.json').read_text()):
    assert run['headSha'] == manifest['candidate_sha']
print('PASS: 17 complete source files (8 Markdown + 9 PNG), sizes/hashes and candidate evidence identities')
