"""Execute the actual workflow selector; synthetic controls are not DUT RED."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


def select(suite, ref):
    workflow = Path(__file__).resolve().parents[4] / '.github/workflows/android-rust-bridge.yml'
    section = workflow.read_text().split('  select:\n', 1)[1].split('  compiling-red:\n', 1)[0]
    code = section.split("          python3 - <<'PY'\n", 1)[1].split('          PY\n', 1)[0]
    code = '\n'.join(line[10:] for line in code.splitlines()) + '\n'
    with tempfile.TemporaryDirectory(prefix='bridge-selector-control-') as tmp:
        output = Path(tmp) / 'output'
        result = subprocess.run([sys.executable, '-B', '-c', code], capture_output=True,
            env=dict(os.environ, REQUESTED_SUITE=suite, SOURCE_REF=ref, GITHUB_OUTPUT=str(output)), timeout=5)
        return result, dict(line.split('=', 1) for line in output.read_text().splitlines()) if output.is_file() else {}


class WorkflowSelectionControls(unittest.TestCase):
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
