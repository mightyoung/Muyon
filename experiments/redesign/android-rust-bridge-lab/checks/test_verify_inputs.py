"""Synthetic packaging controls; actual official AAR/ELF acceptance runs remotely."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile
import verify_inputs as verifier

SCHEMA_BYTES = (verifier.ROOT / verifier.SCHEMA).read_bytes()
SCHEMA = json.loads(SCHEMA_BYTES)


class InputTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='bridge-input-control-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        schema = self.root / verifier.SCHEMA; schema.parent.mkdir(parents=True); schema.write_bytes(SCHEMA_BYTES)
        self.binding = self.root / verifier.BINDING; self.binding.parent.mkdir(parents=True); self.binding.write_bytes(b'fixture binding\n')
        self.config = self.root / verifier.CONFIG; self.config.parent.mkdir(parents=True); self.config.write_bytes(b'fixture config\n')
        self.inputs = self.root / 'bridge-inputs'; self.inputs.mkdir()
        self.aar = self.root / 'fixture.aar'
        self.source = 'a' * 40
        self.value = dict(format_version=1, source_sha=self.source, build_identity=self.source,
                          protocol=1, namespace='muyon_android_contract_bridge', min_api=24,
                          android_binding_sha256=verifier.digest(self.binding),
                          android_config_sha256=verifier.digest(self.config), rust_libraries={},
                          jna={key: child['const'] for key, child in SCHEMA['properties']['jna']['properties'].items() if 'const' in child})
        self.value['jna']['jni_sha256'] = {abi: child['const'] for abi, child in SCHEMA['properties']['jna']['properties']['jni_sha256']['properties'].items()}
        for abi in verifier.ABIS:
            path = f'jniLibs/{abi}/libmuyon_android_contract_bridge.so'
            file = self.inputs / path; file.parent.mkdir(parents=True); file.write_bytes(('synthetic ' + abi).encode())
            self.value['rust_libraries'][abi] = dict(path=path, sha256=verifier.digest(file))
        self.patch = patch.object(verifier, 'ROOT', self.root); self.patch.start(); self.addCleanup(self.patch.stop)
        self.write()

    def write(self):
        (self.inputs / 'bridge-inputs.json').write_text(json.dumps(self.value))

    def verify_without_official_aar(self, source=None):
        # Only cryptographically pinned external artifact dependency is replaced.
        # check_aar's real bytes/zip validation has independent tests below. This
        # synthetic success is not official artifact/native runtime evidence.
        with patch.object(verifier, 'check_aar') as check:
            verifier.verify(self.inputs, source or self.source, self.binding, self.config, self.aar)
            check.assert_called_once_with(self.aar, self.value['jna'])

    def test_closed_synthetic_manifest_and_real_file_hashes(self):
        self.verify_without_official_aar()

    def test_independent_source_and_build_identity(self):
        with self.assertRaisesRegex(verifier.Invalid, '^source_identity$'):
            self.verify_without_official_aar('b' * 40)
        self.value['build_identity'] = 'b' * 40; self.write()
        with self.assertRaisesRegex(verifier.Invalid, '^source_identity$'):
            self.verify_without_official_aar()

    def test_unknown_missing_wrong_types_and_constants_reject(self):
        for key, value in [('unknown', 1), ('protocol', True), ('format_version', 1.0),
                           ('protocol', 2), ('min_api', 26), ('source_sha', 'A' * 40),
                           ('android_binding_sha256', '0' * 64 + '\n'), ('jna', None)]:
            with self.subTest(key=key, value=value):
                bad = copy.deepcopy(self.value); bad[key] = value
                with self.assertRaises(verifier.Invalid):
                    verifier.validate(bad, SCHEMA, SCHEMA['$defs'])
        for key in self.value:
            bad = copy.deepcopy(self.value); del bad[key]
            with self.assertRaisesRegex(verifier.Invalid, '^manifest_shape$'):
                verifier.validate(bad, SCHEMA, SCHEMA['$defs'])

    def test_duplicate_nested_key_trailing_json_and_non_utf8_reject(self):
        for raw in [b'{"protocol":1,"protocol":1}', b'{"jna":{"version":1,"version":1}}', b'{}{}', b'\xff', b'{"x":NaN}']:
            with self.assertRaises(verifier.Invalid):
                verifier.decode(raw)

    def test_mixed_missing_extra_and_modified_native_inputs_reject(self):
        library = self.inputs / self.value['rust_libraries']['arm64-v8a']['path']
        original = library.read_bytes(); library.write_bytes(b'changed')
        with self.assertRaisesRegex(verifier.Invalid, '^rust_library_hash$'):
            self.verify_without_official_aar()
        library.write_bytes(original); library.unlink()
        with self.assertRaisesRegex(verifier.Invalid, '^input_tree$'):
            self.verify_without_official_aar()
        library.write_bytes(original)
        extra = self.inputs / 'jniLibs/x86_64/libjnidispatch.so'; extra.write_bytes(b'extra')
        with self.assertRaisesRegex(verifier.Invalid, '^input_tree$'):
            self.verify_without_official_aar()
        extra.unlink(); library.unlink(); library.symlink_to(self.binding)
        with self.assertRaisesRegex(verifier.Invalid, '^input_tree$'):
            self.verify_without_official_aar()

    def test_fixed_source_paths_and_hashes_reject_substitution(self):
        with self.assertRaisesRegex(verifier.Invalid, '^fixed_source_path$'):
            verifier.verify(self.inputs, self.source, self.root / 'wrong.kt', self.config, self.aar)
        self.binding.write_bytes(b'changed')
        with self.assertRaisesRegex(verifier.Invalid, '^binding_hash$'):
            self.verify_without_official_aar()
        self.binding.write_bytes(b'fixture binding\n'); self.config.write_bytes(b'changed')
        with self.assertRaisesRegex(verifier.Invalid, '^android_config_hash$'):
            self.verify_without_official_aar()

    def test_aar_actual_archive_bytes_and_jni_entries_are_verified(self):
        data = {abi: ('synthetic jni ' + abi).encode() for abi in verifier.ABIS}
        with zipfile.ZipFile(self.aar, 'w') as archive:
            for abi, raw in data.items():
                archive.writestr(f'jni/{abi}/libjnidispatch.so', raw)
        fixture_expected = dict(aar_sha256=verifier.digest(self.aar),
                                jni_sha256={abi: hashlib.sha256(raw).hexdigest() for abi, raw in data.items()})
        verifier.check_aar(self.aar, fixture_expected)
        wrong = copy.deepcopy(fixture_expected); wrong['jni_sha256']['x86_64'] = '0' * 64
        with self.assertRaisesRegex(verifier.Invalid, '^jna_jni_hash$'):
            verifier.check_aar(self.aar, wrong)
        with self.assertRaisesRegex(verifier.Invalid, '^jna_aar_hash$'):
            verifier.check_aar(self.aar, self.value['jna'])
        with zipfile.ZipFile(self.aar, 'w') as archive:
            archive.writestr('jni/arm64-v8a/libjnidispatch.so', data['arm64-v8a'])
        fixture_expected['aar_sha256'] = verifier.digest(self.aar)
        with self.assertRaisesRegex(verifier.Invalid, '^jna_jni_entry$'):
            verifier.check_aar(self.aar, fixture_expected)


if __name__ == '__main__':
    unittest.main(verbosity=2)
