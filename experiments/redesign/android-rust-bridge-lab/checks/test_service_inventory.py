"""Source inventory controls; no synthetic content is native behavior evidence."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

import linux_gate


class ServiceInventoryControls(unittest.TestCase):
    def test_exact_source_blob_names_and_counts_are_required(self):
        validate = getattr(linux_gate, 'service_inventory', None)
        self.assertTrue(callable(validate), 'service source inventory validation is missing')
        frozen = json.loads(Path(__file__).with_name('service_cases.json').read_text())
        with tempfile.TemporaryDirectory(prefix='service-inventory-control-') as tmp:
            root = Path(tmp)
            test_file = root / frozen['test_file']; test_file.parent.mkdir(parents=True)
            body = ''.join('#[test]\nfn ' + name + '() {}\n' for name in frozen['test_names']).encode()
            test_file.write_bytes(body)
            frozen['test_sha256'] = hashlib.sha256(body).hexdigest()
            frozen['test_blob_sha'] = hashlib.sha1(b'blob ' + str(len(body)).encode() + b'\0' + body).hexdigest()
            descriptor = root / 'service_cases.json'
            def write(value):
                descriptor.write_text(json.dumps(value))
            write(frozen)
            self.assertEqual(validate(root, descriptor), frozen)
            for key, value in [('test_sha256', '0' * 64), ('test_blob_sha', '0' * 40),
                               ('test_names', frozen['test_names'][:-1]),
                               ('manifest', '../../Cargo.toml'), ('test_file', '/tmp/elsewhere')]:
                bad = dict(frozen, **{key: value}); write(bad)
                with self.subTest(key=key), self.assertRaises(RuntimeError):
                    validate(root, descriptor)
            for key, value in [('filtered', 2), ('filtered', True), ('target', 'other')]:
                bad = dict(frozen, red=dict(frozen['red'], **{key: value})); write(bad)
                with self.subTest(key=key), self.assertRaises(RuntimeError):
                    validate(root, descriptor)
            write(frozen); test_file.write_bytes(body + b'// changed source\n')
            with self.assertRaises(RuntimeError):
                validate(root, descriptor)

    def test_absent_or_malformed_contract_cannot_fall_back(self):
        validate = getattr(linux_gate, 'service_inventory', None)
        self.assertTrue(callable(validate), 'service source inventory validation is missing')
        with tempfile.TemporaryDirectory(prefix='service-inventory-control-') as tmp:
            root = Path(tmp); descriptor = root / 'absent.json'
            with self.assertRaises(RuntimeError):
                validate(root, descriptor)
            for text in ['{}', '[]', '{', '{"version":1}']:
                descriptor.write_text(text)
                with self.assertRaises(RuntimeError):
                    validate(root, descriptor)


if __name__ == '__main__':
    unittest.main()
