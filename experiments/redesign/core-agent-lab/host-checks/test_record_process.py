"""Recorder checks use explicit fake byte echo; they are not product evidence."""
import json
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest

from inspect_process import inspect
from rejection_oracle import check


class RecorderTests(unittest.TestCase):
    def test_rejection_oracle_rejects_timeout_and_scope_substitution_observations(self):
        check('core_host_protocol', 'host_protocol')
        check('core_host_budget', 'host_budget')
        check('model_failed', 'model_failed')
        # Missing immediate frame bound -> eventual timeout is not a kill.
        for error in ['callback_timeout', 'host_eof', 'core_backend_unavailable']:
            with self.subTest(error=error), self.assertRaisesRegex(
                    AssertionError, '^wrong_rejection_boundary$'):
                check(error, 'host_budget')
        # Missing identifier validation -> ordinary scope denial must fail.
        with self.assertRaisesRegex(AssertionError, '^wrong_rejection_boundary$'):
            check('tool_denied', 'model_failed', prepare_count=1)
        with self.assertRaisesRegex(AssertionError, '^unexpected_prepare_before_argument_rejection$'):
            check('model_failed', 'model_failed', prepare_count=1)
        with self.assertRaisesRegex(AssertionError, '^unexpected_invoke_before_rejection$'):
            check('model_failed', 'model_failed', invoke_count=1)

    def test_terminal_gate_rejects_missing_success_and_skips(self):
        with TemporaryDirectory(prefix='host-gate-selfcheck-') as temporary:
            log = Path(temporary, 'test.log')
            checker = Path(__file__).with_name('verify_run.py')
            cases = [('00:01 +1: All tests passed!\n', 0),
                     ('00:01 +1 ~1: All tests passed!\n', 1),
                     ('00:01 +0: skipped\nAll tests passed!\n', 1),
                     ('00:01 +0 -1: Some tests failed.\n', 1),
                     ('compiler error\n', 1)]
            for text, expected in cases:
                with self.subTest(text=text):
                    log.write_text(text)
                    result = subprocess.run([sys.executable, str(checker), str(log)],
                                            capture_output=True, timeout=5)
                    self.assertEqual(result.returncode, expected)

    def test_exact_binary_roundtrip_and_reaped_child(self):
        with TemporaryDirectory(prefix='host-recorder-selfcheck-') as temporary:
            root = Path(temporary)
            echo = root / 'echo'
            echo.write_text('#!/usr/bin/python3\nimport sys\nb=sys.stdin.buffer.read()\nsys.stdout.buffer.write(b)\nsys.stderr.buffer.write(b"synthetic-stderr")\n')
            echo.chmod(0o700)
            evidence = root / 'evidence'
            payload = bytes(range(256)) * 600
            result = subprocess.run([
                sys.executable, str(Path(__file__).with_name('record_process.py')),
                '--binary', str(echo), '--evidence', str(evidence),
            ], input=payload, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stdout, payload)
            self.assertEqual(result.stderr, b'synthetic-stderr')
            self.assertEqual(inspect(evidence), {'launch_count': 1, 'reaped_count': 1})
            directory = next(evidence.glob('launch-*'))
            self.assertEqual((directory / 'host.bin').read_bytes(), payload)
            self.assertEqual((directory / 'core.bin').read_bytes(), payload)
            self.assertEqual((directory / 'stderr.bin').read_bytes(), b'synthetic-stderr')
            self.assertEqual(json.loads((directory / 'exit.json').read_text()), {'code': 0, 'reaped': True})
            launch = json.loads((directory / 'launch.json').read_text())
            self.assertEqual(launch['binary'], str(echo))
            self.assertFalse(Path('/proc', str(launch['pid'])).exists())

    def test_one_launch_oracle_rejects_two_real_launches_without_overwrite(self):
        with TemporaryDirectory(prefix='host-recorder-two-launches-') as temporary:
            evidence = Path(temporary) / 'evidence'
            recorder = Path(__file__).with_name('record_process.py')
            def launch(payload):
                result = subprocess.run([sys.executable, str(recorder), '--binary',
                    '/bin/cat', '--evidence', str(evidence)], input=payload,
                    capture_output=True, timeout=10)
                self.assertEqual(result.returncode, 0)
                self.assertEqual(result.stdout, payload)
            with ThreadPoolExecutor(max_workers=2) as pool:
                list(pool.map(launch, [b'first-child', b'second-child']))
            self.assertEqual(inspect(evidence, expected_launches=2),
                             {'launch_count': 2, 'reaped_count': 2})
            with self.assertRaisesRegex(AssertionError, '^unexpected_launch_count$'):
                inspect(evidence, expected_launches=1)
            self.assertEqual({path.read_bytes() for path in evidence.glob('launch-*/core.bin')},
                             {b'first-child', b'second-child'})
            next(evidence.glob('launch-*/exit.json')).unlink()
            with self.assertRaisesRegex(AssertionError, '^child_not_reaped$'):
                inspect(evidence, expected_launches=2)


if __name__ == '__main__':
    unittest.main(verbosity=2)
