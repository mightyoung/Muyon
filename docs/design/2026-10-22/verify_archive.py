"""Offline integrity check for the immutable Library intake; no product execution."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent
manifest = json.loads((root / 'sources.json').read_text())
assert len(manifest['files']) == 20
assert len({x['library_file_id'] for x in manifest['files']}) == 20
for item in manifest['files']:
    data = (root / item['path']).read_bytes()
    assert len(data) == item['size_bytes'], item['path']
    assert hashlib.sha256(data).hexdigest() == item['sha256'], item['path']
    assert item['complete'] is True
images = sorted((root / 'ui-v1.0').glob('*.png'))
assert len(images) == 9
assert [x.name[:2] for x in images] == [f'{i:02d}' for i in range(1, 10)]
brand = [x for x in manifest['files'] if x['path'].startswith('brand-originals/')]
assert {x['library_file_id'] for x in brand} == {
    'libfile_318651bdb1008191a7d6c09790e1a885',
    'libfile_3244286245348191aa0b5d9040b48f7f',
    'libfile_0a8ca4ea6fac81919b6d095a4b3890ca',
}
pr = json.loads((root / 'evidence/pr100.json').read_text())
assert pr['headRefOid'] == manifest['candidate_sha']
for run in json.loads((root / 'evidence/candidate-runs.json').read_text()):
    assert run['headSha'] == manifest['candidate_sha']
print('PASS: 20 complete source files (8 Markdown + 9 UI examples + 3 original brand assets), sizes/hashes and candidate evidence identities')
