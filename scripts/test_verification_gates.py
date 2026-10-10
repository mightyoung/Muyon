#!/usr/bin/env python3
"""Exit-status regressions for the actual gates, with offline Flutter fixtures.

Run: python3 scripts/test_verification_gates.py
The fixture copies the gate scripts unchanged; only their external Flutter and
doctor and regression-runner dependencies are replaced. No real package or screenshot test is edited.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
PACKAGES = (
    'packages/muyon_module_api', 'packages/muyon_ui',
    'packages/prototype_module', 'packages/research_module',
    'packages/supplier_core', 'packages/inquiry_module',
    'apps/muyon', 'apps/muyon_ui_preview',
)
FLUTTER = r'''#!/usr/bin/env bash
printf '%s|%s\n' "$PWD" "$*" >> "$CALLS"
case "$1" in
  pub) [[ "$SCENARIO" != pub_failure ]]; exit $? ;;
  analyze)
    if [[ "$SCENARIO" == analysis_failure && "$PWD" == */muyon_module_api ]]; then
      echo 'error • controlled analysis failure'; exit 7
    fi
    exit 0 ;;
  test)
    if [[ "$SCENARIO" == multiple_failures && ( "$PWD" == */muyon_module_api || "$PWD" == */supplier_core ) ]]; then
      echo '00:01 +0 -1: Some tests failed.'; exit 42
    fi
    if [[ "$PWD" == */muyon_module_api ]]; then
      case "$SCENARIO" in
        failure_summary) echo '00:01 +0 -1: Some tests failed.'; exit 7 ;;
        pass_summary_failure) echo '00:01 +1: All tests passed!'; exit 7 ;;
        missing_summary) echo 'runner ended without summary'; exit 0 ;;
        compact_failure) echo '00:01 +0 -1: controlled failure [E]'; echo '00:01 +0 -1: Some tests failed.'; exit 7 ;;
      esac
    fi
    echo '00:01 +1: All tests passed!'; exit 0 ;;
  *) exit 99 ;;
esac
'''


class VerificationGates(unittest.TestCase):
    def run_gate(self, gate, scenario):
        with tempfile.TemporaryDirectory(prefix='muyon-gate-test-') as directory:
            root = Path(directory)
            (root / 'scripts').mkdir()
            (root / 'bin').mkdir()
            for package in PACKAGES:
                (root / package).mkdir(parents=True)
            shutil.copyfile(ROOT / 'scripts' / gate, root / 'scripts' / gate)
            (root / 'scripts/coverage').mkdir()
            for filename in ('check.py', 'test_check.py'):
                (root / 'scripts/coverage' / filename).write_text('pass\n')
            # CI's doctor scenarios are independent of Flutter status propagation.
            (root / 'scripts/test_doctor.sh').write_text(
                '#!/usr/bin/env bash\necho "all 23 scenarios passed"\n')
            # Avoid recursively executing this runner when testing ci.sh's own
            # Flutter handling; the outer test run is the real regression gate.
            (root / 'scripts/test_verification_gates.py').write_text(
                'raise SystemExit(5)\n' if scenario == 'gate_runner_failure' else 'pass\n')
            flutter = root / 'bin/flutter'
            flutter.write_text(FLUTTER)
            flutter.chmod(0o755)
            calls = root / 'calls'
            env = dict(os.environ, PATH=str(root / 'bin') + ':' + os.environ['PATH'],
                       SCENARIO=scenario, CALLS=str(calls))
            result = subprocess.run(['/bin/bash', str(root / 'scripts' / gate)],
                                    env=env, text=True, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, timeout=20)
            return result, calls.read_text().splitlines()

    def check_scenario(self, scenario, expected):
        for gate in ('verify.sh', 'ci.sh'):
            with self.subTest(gate=gate, scenario=scenario):
                result, calls = self.run_gate(gate, scenario)
                self.assertEqual(result.returncode,
                                 expected[gate] if isinstance(expected, dict) else expected,
                                 result.stdout)
                test_calls = [call for call in calls if '|test ' in call]
                if scenario == 'pub_failure':
                    self.assertEqual(test_calls, [])
                else:
                    # A failing first suite must not prevent later suites or inquiry
                    # screenshots from being invoked with the original target.
                    self.assertEqual(len(test_calls), 8, result.stdout)
                    if scenario == 'multiple_failures':
                        self.assertIn('module_api: FAILED', result.stdout)
                        self.assertIn('supplier_core: FAILED', result.stdout)
                        self.assertIn('inquiry: ok', result.stdout)
                    self.assertIn('../../packages/inquiry_module/test', test_calls[-1])
                    if gate == 'ci.sh':
                        self.assertTrue(all('--coverage ' in call for call in test_calls))
                        self.assertEqual(len({call.split('--coverage-path ')[1].split(' ')[0]
                                              for call in test_calls}), 8)
                    self.assertFalse(any('--exclude-tags' in call or '--tags' in call
                                         for call in test_calls))

    def test_success(self):
        self.check_scenario('success', 0)

    def test_nonzero_with_failure_summary_without_error_marker(self):
        self.check_scenario('failure_summary', 1)

    def test_nonzero_after_success_summary(self):
        self.check_scenario('pass_summary_failure', 1)

    def test_multiple_failures_are_reported_and_later_suites_run(self):
        self.check_scenario('multiple_failures', 1)

    def test_ci_fails_when_its_gate_regressions_fail(self):
        self.check_scenario('gate_runner_failure', {'verify.sh': 0, 'ci.sh': 1})

    def test_missing_summary(self):
        self.check_scenario('missing_summary', 1)

    def test_compact_error_marker(self):
        self.check_scenario('compact_failure', 1)

    def test_analysis_failure(self):
        self.check_scenario('analysis_failure', 1)

    def test_pub_failure(self):
        self.check_scenario('pub_failure', 1)


if __name__ == '__main__':
    unittest.main(verbosity=2)
