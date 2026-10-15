"""Classifier self checks, not real Rust/Dart behavior evidence."""
import json
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest

from ci_evidence import DART_CASES, DART_MARKER, DART_RED, REGISTRATION_CASES, RUST_CASES, RUST_MARKER, RUST_RED, dart_result, rust_result


def dart_rows(red=False):
    rows = []
    for identifier, name in enumerate([DART_RED] if red else sorted(DART_CASES)):
        rows.append({'type': 'testStart', 'test': {'id': identifier, 'name': name}})
        if red:
            rows.append({'type': 'error', 'testID': identifier, 'isFailure': True, 'error': DART_MARKER})
        rows.append({'type': 'testDone', 'testID': identifier,
                     'result': 'failure' if red else 'success', 'skipped': False})
    return rows + [{'type': 'done', 'success': not red}]


class EvidenceTests(unittest.TestCase):
    def test_missing_or_malformed_reporter_is_invalid_with_a_retained_verdict(self):
        with TemporaryDirectory(prefix='plugin-evidence-selfcheck-') as temporary:
            root = Path(temporary)
            raw = root / 'report.jsonl'
            output = root / 'verdict.json'
            command = [sys.executable, '-B', str(Path(__file__).with_name('ci_evidence.py')),
                       '--language', 'dart', '--mode', 'red', '--log', str(raw),
                       '--exit-code', '1', '--output', str(output)]
            for content in [None, 'not reporter JSON', '5\n']:
                if content is not None:
                    raw.write_text(content)
                run = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                self.assertEqual(run.returncode, 1)
                self.assertEqual(run.stderr, b'')
                result = json.loads(output.read_text())
                self.assertFalse(result['accepted'])
                self.assertFalse(result['compiled'])

    def test_rust_red_requires_one_named_executed_panic_not_compilation(self):
        raw = (f'Finished `test` profile [unoptimized]\nRunning tests/registration.rs (target/debug/deps/registration)\nrunning 1 test\n'
               f'thread \'{RUST_RED}\' panicked at tests/registration.rs:20:5:\n{RUST_MARKER}\n'
               f'test {RUST_RED} ... FAILED\n'
               'test result: FAILED. 0 passed; 1 failed; 0 ignored; 0 measured; 7 filtered out;\n')
        self.assertTrue(rust_result(raw, 101, True)['accepted'])
        for bad, code in [(raw, 0), (raw, 124), (raw.replace('Finished', 'Compiling'), 101),
                          (raw.replace(RUST_MARKER, 'other'), 101),
                          (raw.replace(RUST_RED, 'other'), 101), (raw + 'timed out', 101),
                          (raw.replace(RUST_MARKER, 'wrong assertion') + RUST_MARKER, 101),
                          (raw + 'test other ... FAILED\n', 101)]:
            self.assertFalse(rust_result(bad, code, True)['accepted'])

    def test_rust_full_requires_exact_sixteen_and_zero_skip(self):
        raw = 'Finished `test` profile [unoptimized]\n'
        for target, names in [('registration', REGISTRATION_CASES), ('read_contract', RUST_CASES - REGISTRATION_CASES)]:
            raw += f'Running tests/{target}.rs (target/debug/deps/{target})\n'
            raw += ''.join(f'test {name} ... ok\n' for name in sorted(names))
            raw += 'test result: ok. 8 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out;\n'
        raw += 'Doc-tests muyon_plugin_contract_lab\ntest result: ok. 0 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out;\n'
        self.assertTrue(rust_result(raw, 0)['accepted'])
        self.assertEqual(rust_result(raw, 0)['doc_test_count'], 0)
        self.assertFalse(rust_result(raw.replace('8 passed', '7 passed'), 0)['accepted'])
        self.assertFalse(rust_result(raw.replace('0 ignored', '1 ignored'), 0)['accepted'])
        self.assertFalse(rust_result(raw + 'test extra ... ok\n', 0)['accepted'])
        self.assertFalse(rust_result(raw.replace('tests/registration.rs', 'tests/other.rs'), 0)['accepted'])

    def test_dart_red_rejects_timeout_setup_extra_errors_and_skips(self):
        rows = dart_rows(True)
        self.assertTrue(dart_result(rows, 1, True)['accepted'])
        self.assertFalse(dart_result(rows, 0, True)['accepted'])
        self.assertFalse(dart_result([], 1, True)['accepted'])
        for change in ['exception', 'timeout', 'marker', 'skip', 'extra']:
            candidate = dart_rows(True)
            if change == 'exception':
                candidate[1]['isFailure'] = False
            elif change == 'timeout':
                candidate[1]['error'] += ' TimeoutException'
            elif change == 'marker':
                candidate[1]['error'] = 'other boundary'
            elif change == 'skip':
                candidate[2]['skipped'] = True
            else:
                candidate.append({'type': 'error', 'testID': 0, 'isFailure': False, 'error': 'teardown'})
            self.assertFalse(dart_result(candidate, 1, True)['accepted'])

    def test_dart_full_requires_exact_twelve_terminal_passes(self):
        self.assertTrue(dart_result(dart_rows(), 0)['accepted'])
        self.assertFalse(dart_result(dart_rows()[:-1], 0)['accepted'])
        self.assertFalse(dart_result(dart_rows()[2:], 0)['accepted'])
        skipped = dart_rows()
        skipped[1]['skipped'] = True
        self.assertFalse(dart_result(skipped, 0)['accepted'])
        extra = dart_rows() + [{'type': 'testStart', 'test': {'id': 100, 'name': 'unplanned'}}]
        self.assertFalse(dart_result(extra, 0)['accepted'])
        duplicate = dart_rows() + [dart_rows()[0]]
        self.assertFalse(dart_result(duplicate, 0)['accepted'])

    def test_existing_regression_scope_records_count_without_weakening_fixed_full(self):
        rows = [{'type': 'testStart', 'test': {'id': 8, 'name': 'an existing regression'}},
                {'type': 'testDone', 'testID': 8, 'result': 'success', 'skipped': False},
                {'type': 'done', 'success': True}]
        result = dart_result(rows, 0, existing_regressions=True)
        self.assertTrue(result['accepted'])
        self.assertEqual(result['test_count'], 1)
        self.assertEqual(result['count_contract'], 'existing_file_scope')
        self.assertFalse(dart_result(rows, 0)['accepted'])
        self.assertFalse(dart_result([], 0, existing_regressions=True)['accepted'])
        rows[1]['skipped'] = True
        self.assertFalse(dart_result(rows, 0, existing_regressions=True)['accepted'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
