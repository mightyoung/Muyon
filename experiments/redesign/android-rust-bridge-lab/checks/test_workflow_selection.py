"""Execute the actual workflow selector; synthetic controls are not DUT RED."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


def select(suite, ref, event='workflow_dispatch'):
    workflow = Path(__file__).resolve().parents[4] / '.github/workflows/android-rust-bridge.yml'
    section = workflow.read_text().split('  select:\n', 1)[1].split('  compiling-red:\n', 1)[0]
    code = section.split("          python3 - <<'PY'\n", 1)[1].split('          PY\n', 1)[0]
    code = '\n'.join(line[10:] for line in code.splitlines()) + '\n'
    with tempfile.TemporaryDirectory(prefix='bridge-selector-control-') as tmp:
        output = Path(tmp) / 'output'
        result = subprocess.run([sys.executable, '-B', '-c', code], capture_output=True,
            env=dict(os.environ, REQUESTED_SUITE=suite, SOURCE_REF=ref, EVENT_NAME=event, GITHUB_OUTPUT=str(output)), timeout=5)
        return result, dict(line.split('=', 1) for line in output.read_text().splitlines()) if output.is_file() else {}


class WorkflowSelectionControls(unittest.TestCase):
    def test_combined_candidate_pr_explicitly_selects_full_without_duplicate_push(self):
        ref = 'lab/leaderb-batch4-combined-20261018'
        result, selected = select('', ref, 'pull_request')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(selected, {'mode': 'full', 'red': '[]'})
        workflow = Path(__file__).resolve().parents[4] / '.github/workflows/android-rust-bridge.yml'
        push = workflow.read_text().split('  push:\n', 1)[1].split('  pull_request:\n', 1)[0]
        self.assertIn("branches: ['lab/android-rust-bridge-*']", push)
        self.assertNotIn("'lab/leaderb-batch4-combined-20261018'", push)

    def test_unrelated_pr_is_explicitly_unselected_without_skipping_selector(self):
        for ref in ('feature/ordinary', 'lab/leaderb-batch4-combined-20261018-other',
                    'lab/leaderb-batch4-combined', 'lab/leaderb-batch3-combined-20261018'):
            result, selected = select('', ref, 'pull_request')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(selected, {'mode': 'unselected', 'red': '[]'}, ref)
        workflow = Path(__file__).resolve().parents[4] / '.github/workflows/android-rust-bridge.yml'
        header = workflow.read_text().split('  select:\n', 1)[1].split('    steps:\n', 1)[0]
        self.assertNotIn('    if:', header)

    def test_scoped_android_pr_preserves_original_red_and_checkpoint_selection(self):
        for mode in ('full', 'rust-red', 'jvm-red', 'service-host-checkpoint', 'service-host-green', 'service-oracle-red', 'service-temp-red'):
            ref = 'lab/android-rust-bridge-' + ('integration' if mode == 'full' else mode) + '-20261015'
            result, selected = select('', ref, 'pull_request')
            self.assertEqual(result.returncode, 0, result.stderr)
            red = [mode] if mode in ('rust-red', 'jvm-red') else []
            self.assertEqual(selected, {'mode': 'red' if red else mode, 'red': json.dumps(red)})

    def test_service_and_original_red_refs_select_required_modes(self):
        for mode in ['rust-red', 'jvm-red', 'service-rust-red', 'service-jvm-red']:
            for suite, ref in [(mode, 'lab/android-rust-bridge-integration-20261015'),
                               ('', 'lab/android-rust-bridge-' + mode + '-20261015')]:
                with self.subTest(mode=mode, suite=suite):
                    result, selected = select(suite, ref)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(selected, {'mode': 'red', 'red': json.dumps([mode])})

    def test_full_default_original_pair_and_invalid_suite(self):
        for suite, ref in [('', 'lab/android-rust-bridge-integration-20261015'),
                           ('full', 'lab/android-rust-bridge-service-rust-red-20261015')]:
            result, selected = select(suite, ref)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(selected, {'mode': 'full', 'red': '[]'})
        result, selected = select('red', 'ignored')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(selected, {'mode': 'red', 'red': '["rust-red", "jvm-red"]'})
        result, selected = select('service-unknown-red', 'ignored')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(selected, {})
        self.assertEqual(result.stderr, b'invalid_suite\n')


if __name__ == '__main__':
    unittest.main()
