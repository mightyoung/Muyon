"""Regression controls for the formal combined gate; synthetic logs are not DUT evidence."""
import ast
from pathlib import Path
import unittest
from full import rust
from test_http_batch import transcript


class CombinedGateTests(unittest.TestCase):
    def test_formal_combined_contract_accepts_complete_inventory(self):
        for component in ('core', 'plugin', 'host'):
            self.assertTrue(rust(component, transcript(component), 0, contract='combined')['accepted'])

    def test_formal_combined_contract_rejects_every_case_omission(self):
        from http_batch import contract
        for component, spec in contract()['components'].items():
            raw = transcript(component)
            for group in spec['groups'].values():
                for name in group['names']:
                    self.assertFalse(rust(component, raw.replace(f'test {name} ... ok', ''), 0, contract='combined')['accepted'])

    def test_expected_source_rejects_wrong_head_dirty_tree_and_short_sha(self):
        from source_identity import validate
        import subprocess, tempfile
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(['git', 'init', '-q', directory], check=True)
            subprocess.run(['git', '-C', directory, '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '--allow-empty', '-qm', 'test'], check=True)
            head = subprocess.check_output(['git', '-C', directory, 'rev-parse', 'HEAD'], text=True).strip()
            self.assertEqual(validate(root, head)['source_sha'], head)
            for bad in (head[:8], '0' * 40, 'HEAD'):
                with self.assertRaises(RuntimeError): validate(root, bad)
            (root / 'unexpected').write_text('dirty')
            with self.assertRaises(RuntimeError): validate(root, head)

    def test_missing_manifest_is_never_reported_as_verified(self):
        from combined_gate import binary_integrity
        import tempfile
        with tempfile.TemporaryDirectory() as directory:
            evidence = Path(directory)
            for component in ('core', 'plugin', 'host'):
                result = binary_integrity(component, evidence, evidence)
                self.assertFalse(result['verified'])
                self.assertEqual(result['state'], 'missing_required_manifest')
            result = binary_integrity('http', evidence, evidence)
            self.assertIsNone(result['verified'])
            self.assertEqual(result['state'], 'not_recorded')
            result = binary_integrity('native', evidence, evidence)
            self.assertFalse(result['verified'])
            self.assertEqual(result['state'], 'missing_native_summary')

    def test_retained_binary_manifest_detects_actual_byte_change(self):
        from combined_gate import binary_integrity
        import hashlib, tempfile
        with tempfile.TemporaryDirectory() as directory:
            evidence = Path(directory)
            executable = evidence / 'baseline'
            executable.write_bytes(b'compiled baseline bytes')
            manifest = evidence / 'binary-sha256.txt'
            manifest.write_text(hashlib.sha256(executable.read_bytes()).hexdigest() + '  ' + str(executable) + '\n')
            self.assertTrue(binary_integrity('core', evidence, evidence)['verified'])
            executable.write_bytes(b'changed baseline bytes')
            self.assertFalse(binary_integrity('core', evidence, evidence)['verified'])

    def test_current_legacy_anchors_are_unique(self):
        core = Path(__file__).resolve().parents[2] / 'core-agent-lab/core'
        tree = ast.parse((core / 'mutations.py').read_text())
        mutations = next(ast.literal_eval(n.value) for n in tree.body if isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'mutations' for t in n.targets))
        self.assertEqual(len(mutations), 16)
        for name, path, before, after in mutations:
            self.assertEqual((core / path).read_text().count(before), 1, name)


if __name__ == '__main__':
    unittest.main(verbosity=2)
