"""Supply-chain invariants: catch source drift and dictionary/config swaps."""
import hashlib
import json
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
class LockTests(unittest.TestCase):
    def test_unchanged_upstream_sources_and_licensed_fixtures(self):
        lock=json.loads((ROOT/'upstream.lock.json').read_text())
        for item in lock['files']:
            self.assertEqual(hashlib.sha256((ROOT/item['path']).read_bytes()).hexdigest(),item['sha256'],item['path'])
        models=json.loads((ROOT/'models.lock.json').read_text())
        for size in ['tiny','small']:
            m=next(m for m in models['models'] if m['repository']==f'PaddlePaddle/PP-OCRv6_{size}_rec_onnx')
            config=next(f for f in m['files'] if f['file']=='inference.yml')
            self.assertEqual(hashlib.sha256((ROOT/f'fixtures/{size}-rec.yml').read_bytes()).hexdigest(),config['sha256'])
            self.assertEqual(m['license'],'apache-2.0')
    def test_reference_adaptation_is_fixed(self):
        lock=json.loads((ROOT/'checks/reference-sources.json').read_text())
        for f in lock['files']:
            if 'localSha256' in f:
                self.assertEqual(hashlib.sha256((ROOT/'checks'/f['localFile']).read_bytes()).hexdigest(),f['localSha256'])
if __name__=='__main__':unittest.main()
