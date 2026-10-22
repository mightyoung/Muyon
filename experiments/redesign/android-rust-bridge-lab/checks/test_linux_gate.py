"""Light controls only; no compiler/native/Android outcome is synthesized here."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import linux_gate as gate


class RunnerControls(unittest.TestCase):
    def test_exact_static_inventory_and_duplicate_rejection(self):
        with tempfile.TemporaryDirectory() as folder:
            core = Path(folder)
            (core / 'tests').mkdir(); (core / 'src').mkdir()
            integration = core / 'tests/bridge_contract.rs'
            unit = core / 'src/lib.rs'
            integration.write_text('\n'.join(f'#[test]\nfn {name}() {{}}' for name in gate.INTEGRATION))
            unit.write_text('\n'.join(f'#[test]\nfn {name}() {{}}' for name in gate.UNIT))
            with patch.object(gate, 'CORE', core):
                gate.inventory()
                integration.write_text(integration.read_text() + '\n#[test]\nfn bundled_contract_reaches_rust_catalog() {}')
                with self.assertRaisesRegex(RuntimeError, 'fixed_test_inventory_changed'):
                    gate.inventory()

    def test_actual_exit_is_preserved_and_setup_failure_rejects(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.assertEqual(gate.run([sys.executable, '-c', 'raise SystemExit(101)'],
                root / 'behavior.log', os.environ.copy(), cwd=root, required=False), 101)
            with self.assertRaisesRegex(RuntimeError, 'command_invalid_or_failed'):
                gate.run([sys.executable, '-c', 'raise SystemExit(1)'],
                    root / 'setup.log', os.environ.copy(), cwd=root)

    def test_actual_watchdog_reaps_owned_process_and_remains_invalid(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            with self.assertRaisesRegex(RuntimeError, 'command_invalid_or_failed'):
                gate.run([sys.executable, '-c', 'import time; time.sleep(30)'],
                    root / 'timeout.log', os.environ.copy(), cwd=root, timeout=0.1, required=False)
            import json
            record = json.loads((root / 'timeout.log.json').read_text())
            self.assertEqual(record['exit_code'], 124)
            self.assertTrue(record['timed_out'])
            self.assertTrue(record['forced_owned_group_cleanup'])


if __name__ == '__main__':
    unittest.main()
