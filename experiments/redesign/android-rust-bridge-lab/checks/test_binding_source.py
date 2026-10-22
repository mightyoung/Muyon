"""Synthetic source-transfer controls; no generated/native runtime evidence."""
import base64
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


PREFIX = 'ANDROID_BRIDGE_BINDING_SOURCE '
RELATIVE = 'android/com/mightyoung/muyon/androidbridge/muyon_android_contract_bridge.kt'


class BindingSourceControls(unittest.TestCase):
    def api(self):
        path = Path(__file__).with_name('binding_source.py')
        self.assertTrue(path.is_file(), 'bounded binding-source transfer is missing')
        spec = importlib.util.spec_from_file_location('binding_source_control', path)
        module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        return module

    def fixture(self, root):
        body = ('// synthetic generated-source sibling\npackage example\n' + 'x' * 9000).encode()
        path = root / RELATIVE; path.parent.mkdir(parents=True); path.write_bytes(body)
        expected = dict(source_sha='a' * 40, library_sha256='b' * 64, bindgen_sha256='c' * 64,
                        android_config_sha256='d' * 64, android_binding_sha256=hashlib.sha256(body).hexdigest())
        return body, path, expected

    def test_bounded_source_roundtrip_raw_and_ordinary_github_log(self):
        api = self.api()
        with tempfile.TemporaryDirectory(prefix='binding-source-control-') as tmp:
            root = Path(tmp); body, _, expected = self.fixture(root); output = io.StringIO()
            api.emit(root, expected, output)
            raw = output.getvalue()
            decoded, manifest = api.decode(raw, expected)
            self.assertEqual(decoded, body)
            self.assertEqual(manifest['path'], RELATIVE)
            wrapped = '\n'.join('job\tstep\t2026-10-15T12:00:00.1234567Z ' + line for line in raw.splitlines())
            self.assertEqual(api.decode(wrapped, expected)[0], body)

    def test_missing_duplicate_reordered_truncated_or_corrupt_payload_rejects(self):
        api = self.api()
        with tempfile.TemporaryDirectory(prefix='binding-source-control-') as tmp:
            root = Path(tmp); _, _, expected = self.fixture(root); output = io.StringIO()
            api.emit(root, expected, output); lines = output.getvalue().splitlines()
            for bad in [lines[1:], lines[:-1], lines + lines, lines[:2] + lines[1:],
                        [lines[0], lines[2], lines[1]] + lines[3:], lines[:1] + lines[2:]]:
                with self.assertRaises(ValueError): api.decode('\n'.join(bad), expected)
            for index, key, value in [(0, 'bytes', True), (0, 'bytes', 1048577),
                    (0, 'source_sha', 'e' * 40), (0, 'profile', 'jvm'), (0, 'path', '../elsewhere'),
                    (1, 'index', True), (1, 'index', 9), (1, 'data', '!bad!'),
                    (-1, 'android_binding_sha256', 'f' * 64)]:
                records = [json.loads(line[len(PREFIX):]) for line in lines]
                records[index][key] = value
                with self.subTest(key=key), self.assertRaises(ValueError):
                    api.decode('\n'.join(PREFIX + json.dumps(record) for record in records), expected)
            duplicate = lines[0].replace('{', '{"kind":"manifest",', 1)
            with self.assertRaises(ValueError): api.decode('\n'.join([duplicate] + lines[1:]), expected)
            with self.assertRaises(ValueError): api.decode('untrusted-prefix ' + output.getvalue(), expected)

    def test_encoder_refuses_oversize_wrong_hash_binary_or_symlink_without_partial_output(self):
        api = self.api()
        with tempfile.TemporaryDirectory(prefix='binding-source-control-') as tmp:
            root = Path(tmp); _, path, expected = self.fixture(root)
            for body in [b'x' * 1048577, b'\xff', b'changed']:
                path.write_bytes(body); output = io.StringIO()
                pins = dict(expected, android_binding_sha256=hashlib.sha256(body).hexdigest()) if body != b'changed' else expected
                with self.assertRaises(ValueError): api.emit(root, pins, output)
                self.assertEqual(output.getvalue(), '')
            boundary = b'x' * 1048576
            path.write_bytes(boundary)
            pins = dict(expected, android_binding_sha256=hashlib.sha256(boundary).hexdigest())
            output = io.StringIO(); api.emit(root, pins, output)
            self.assertEqual(api.decode(output.getvalue(), pins)[0], boundary)
            path.unlink(); other = root / 'other'; other.write_bytes(b'synthetic')
            path.symlink_to(other); output = io.StringIO()
            with self.assertRaisesRegex(ValueError, 'binding_source_symlink'): api.emit(root, expected, output)
            self.assertEqual(output.getvalue(), '')

    def test_diagnostic_flag_is_rejected_before_setup_for_any_other_mode(self):
        gate = Path(__file__).with_name('linux_gate.py')
        with tempfile.TemporaryDirectory(prefix='binding-source-cli-control-') as tmp:
            for mode in ['rust-red', 'jvm-red', 'service-rust-red', 'full']:
                result = subprocess.run([sys.executable, '-B', str(gate), '--mode', mode,
                    '--evidence-dir', tmp, '--work-dir', tmp, '--emit-android-source'],
                    capture_output=True, timeout=5)
                self.assertEqual(result.returncode, 2)
                self.assertIn(b'android source emission requires service-jvm-red', result.stderr)
                self.assertEqual(result.stdout, b'')

    def test_decoder_rejects_unknown_keys_or_inconsistent_byte_and_chunk_counts(self):
        api = self.api()
        with tempfile.TemporaryDirectory(prefix='binding-source-control-') as tmp:
            root = Path(tmp); _, _, expected = self.fixture(root); output = io.StringIO()
            api.emit(root, expected, output)
            original = [json.loads(line[len(PREFIX):]) for line in output.getvalue().splitlines()]
            for index, key, value in [(0, 'extra', 1), (1, 'extra', 1), (-1, 'extra', 1),
                                     (0, 'chunks', 99), (0, 'bytes', 1), (0, 'chunk_chars', 4000),
                                     (1, 'data', base64.b64encode(b'short').decode())]:
                records = json.loads(json.dumps(original)); records[index][key] = value
                with self.assertRaises(ValueError):
                    api.decode('\n'.join(PREFIX + json.dumps(record) for record in records), expected)


if __name__ == '__main__':
    unittest.main()
