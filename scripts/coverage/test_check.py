import copy
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('checker', Path(__file__).with_name('check.py'))
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class CoverageContract(unittest.TestCase):
    def contract(self):
        return dict(measurement_version=1, measurement_sha256='fixed', platform='linux',
                    flutter_version='3.47.5', suites=['a'], exclusions=[],
                    gates={'critical/': dict(source_files=['critical/a.dart'],
                          loaded_denominator={'critical/a.dart': {'line_count': 2, 'line_set_sha256': 'before'}},
                          loaded_executable_lines=2, hit_lines=2)})

    def test_missing_report_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, 'missing/empty'):
                checker.measure(Path(directory), Path(directory))

    def test_missing_report_cli_fails(self):
        import subprocess
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(
                ['python3', str(Path(__file__).with_name('check.py')),
                 '--reports', directory, '--output', str(Path(directory) / 'summary.json')],
                text=True, capture_output=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn('missing/empty', result.stdout)

    def test_per_file_decrease_cannot_hide_behind_scope_improvement(self):
        baseline = self.contract()
        baseline['gates']['critical/']['file_hit_lines'] = {'a.dart': 2, 'b.dart': 0}
        actual = copy.deepcopy(baseline)
        actual['gates']['critical/']['file_hit_lines'] = {'a.dart': 1, 'b.dart': 2}
        actual['gates']['critical/']['hit_lines'] = 3
        self.assertTrue(any('coverage decrease: a.dart' in e
                            for e in checker.compare(actual, baseline)))

    def test_equal_passes(self):
        self.assertEqual(checker.compare(self.contract(), self.contract()), [])

    def test_decrease_fails(self):
        baseline = self.contract()
        actual = copy.deepcopy(baseline)
        actual['gates']['critical/']['hit_lines'] = 1
        self.assertTrue(any('decrease' in e for e in checker.compare(actual, baseline)))

    def test_line_identity_drift_even_at_equal_count_fails(self):
        baseline = self.contract()
        actual = copy.deepcopy(baseline)
        actual['gates']['critical/']['loaded_denominator']['critical/a.dart']['line_set_sha256'] = 'after'
        self.assertTrue(any('drift' in e for e in checker.compare(actual, baseline)))

    def test_unloaded_source_added_fails(self):
        baseline = self.contract()
        actual = copy.deepcopy(baseline)
        actual['gates']['critical/']['source_files'].append('critical/unloaded.dart')
        self.assertTrue(any('drift' in e for e in checker.compare(actual, baseline)))

    def test_measurement_version_change_fails(self):
        baseline = self.contract()
        actual = copy.deepcopy(baseline)
        actual['measurement_version'] = 2
        self.assertTrue(checker.compare(actual, baseline))

    def test_merge_duplicate_hits_and_keep_unloaded_unknown(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for package in checker.PACKAGES:
                (root / package / 'lib').mkdir(parents=True)
                (root / package / 'lib/a.dart').write_text('not a denominator')
                (root / package / 'lib/unloaded.dart').write_text('not LCOV')
            reports = root / 'reports'
            for i, suite in enumerate(checker.SUITES):
                (reports / suite).mkdir(parents=True)
                package = checker.WORKING_DIRS[suite]
                source = '../../packages/inquiry_module/lib/a.dart' if suite == 'inquiry' else 'lib/a.dart'
                (reports / suite / 'lcov.info').write_text(
                    f'SF:{source}\nDA:1,1\nDA:3,0\nend_of_record\n'
                    f'SF:{root / checker.PACKAGES[0] / "lib/a.dart"}\nDA:3,1\nend_of_record\n')
            # Measure provenance without requiring a git repository fixture.
            from unittest.mock import patch
            with patch.object(checker.subprocess, 'check_output', return_value='fixed\n'):
                actual = checker.measure(root, reports)
            data = actual['packages'][checker.PACKAGES[0]]
            self.assertEqual((data['hit_lines'], data['loaded_executable_lines']), (2, 2))
            self.assertEqual(actual['packages']['packages/inquiry_module']['hit_lines'], 1)
            self.assertEqual(actual['packages']['apps/muyon']['hit_lines'], 1)
            self.assertEqual(data['unloaded_executable_denominator'], 'unknown')
            self.assertIn(checker.PACKAGES[0] + '/lib/unloaded.dart', data['unloaded_source_files'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
