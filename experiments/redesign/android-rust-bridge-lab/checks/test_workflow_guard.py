"""Execute the actual constant aggregate guard; GitHub scheduling remains remote."""
import os
from pathlib import Path
import subprocess
import sys
import unittest


class AggregateGuardControl(unittest.TestCase):
    def test_actual_guard_and_failclosed_scheduling_expression(self):
        workflow = Path(__file__).resolve().parents[4] / '.github/workflows/android-rust-bridge.yml'
        aggregate = workflow.read_text().split('  required-full:\n', 1)[1]
        self.assertIn("if: always() && (needs.select.outputs.mode == 'full' || needs.select.result != 'success')", aggregate)
        before_checkout = aggregate.split('      - uses: actions/checkout', 1)[0]
        code = before_checkout.split("          python3 - <<'PY'\n", 1)[1].split('          PY\n', 1)[0]
        code = '\n'.join(line[10:] for line in code.splitlines()) + '\n'
        keys = ['SELECT_RESULT', 'LINUX_RESULT', 'ANDROID_RESULT']
        env = dict(os.environ, **{key: 'success' for key in keys})
        valid = subprocess.run([sys.executable, '-B', '-c', code], env=env, capture_output=True, timeout=5)
        self.assertEqual(valid.returncode, 0)
        self.assertEqual(valid.stdout, b'ANDROID_BRIDGE_ALL_PRODUCERS_SUCCESS\n')
        for key in keys:
            for status in ['failure', 'cancelled', 'skipped', '']:
                with self.subTest(key=key, status=status):
                    invalid = subprocess.run([sys.executable, '-B', '-c', code],
                        env=dict(env, **{key: status}), capture_output=True, timeout=5)
                    self.assertNotEqual(invalid.returncode, 0)
                    self.assertEqual(invalid.stdout, b'')
                    self.assertEqual(invalid.stderr, b'ANDROID_BRIDGE_PRODUCER_REQUIRED\n')


if __name__ == '__main__':
    unittest.main()
