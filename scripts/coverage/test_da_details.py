import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('details', Path(__file__).with_name('da_details.py'))
diagnostic = importlib.util.module_from_spec(spec)
spec.loader.exec_module(diagnostic)


class DaDetails(unittest.TestCase):
    def measure(self, first, second=''):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / diagnostic.FILES[0]
            path.parent.mkdir(parents=True)
            path.write_text('this file text is not an executable denominator')
            reports = root / 'reports'
            (reports / 'module_api').mkdir(parents=True)
            (reports / 'host').mkdir()
            (reports / 'module_api/lcov.info').write_text('SF:lib/src/ui/snapshot.dart\n' + first)
            (reports / 'host/lcov.info').write_text('SF:../../packages/muyon_module_api/lib/src/ui/snapshot.dart\n' + second)
            with patch.object(diagnostic.subprocess, 'check_output', return_value='fixed-source\n'):
                return diagnostic.details(root, reports)

    def test_exact_zero_da_and_union_hit(self):
        result = self.measure('DA:17,0\nDA:21,1\nDA:42,0\n', 'DA:17,1\n')
        data = result['files'][diagnostic.FILES[0]]
        self.assertEqual(data['da_line_ids'], [17, 21, 42])
        self.assertEqual(data['uncovered_da_line_ids'], [42])
        self.assertEqual(data['loaded_executable_lines'], 3)
        self.assertEqual(data['hit_lines'], 2)
        self.assertEqual(result['source_sha'], 'fixed-source')

    def test_unreported_source_is_unknown_not_zero(self):
        result = self.measure('DA:17,1\n')
        data = result['files'][diagnostic.FILES[-1]]
        self.assertEqual(data['status'], 'no_DA_records')
        self.assertEqual(data['uncovered_da_line_ids'], 'unknown')
        self.assertEqual(data['loaded_executable_lines'], 'unknown')

    def test_missing_suite_evidence_is_explicit(self):
        result = self.measure('DA:17,1\n')
        self.assertIn('inquiry', result['missing_suite_reports'])
        self.assertNotIn('module_api', result['missing_suite_reports'])

    def test_invalid_da_fails(self):
        for record in ('DA:0,1\n', 'DA:17,-1\n', 'DA:bad,1\n', 'DA:17\n'):
            with self.subTest(record=record):
                with self.assertRaises(ValueError):
                    self.measure(record)


if __name__ == '__main__':
    unittest.main(verbosity=2)
