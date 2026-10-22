"""Checker self-tests only. Synthetic files/marker children are not Rust evidence."""
import os
from pathlib import Path
import signal
from tempfile import TemporaryDirectory
import unittest

import process


class HarnessTests(unittest.TestCase):
    def test_observation_rejects_duplicate_or_non_fields(self):
        self.assertEqual(process.observation('status=ready\nreceipt=\n'), {'status': 'ready', 'receipt': ''})
        for text in ['status=ready\nstatus=completed\n', 'not-an-observation\n', '=empty-key\n']:
            with self.subTest(text=text), self.assertRaises(AssertionError):
                process.observation(text)

    def test_physical_count_value_and_receipt_uniqueness_are_independent(self):
        valid = ('CORE_EFFECT_V1\ncount\t1\nvalue\t41\n'
                 'receipt\tI1\tT1\tA1\tM1\t53\t41\tR1\n')
        variants = [valid.replace('count\t1', 'count\t2'),
                    valid.replace('value\t41', 'value\t42'),
                    valid.replace('CORE_EFFECT_V1', 'WRONG'),
                    valid.replace('count\t1', 'count\t2') + valid.splitlines()[-1] + '\n']
        with TemporaryDirectory(prefix='core-agent-harness-') as temporary:
            directory = Path(temporary)
            path = directory / 'effects.db'
            path.write_text(valid)
            self.assertEqual(process.physical(directory)['count'], 1)
            self.assertEqual(process.physical(directory)['rows'][0][7], 'R1')
            for text in variants:
                path.write_text(text)
                with self.subTest(text=text), self.assertRaises(AssertionError):
                    process.physical(directory)

    def test_missing_effect_file_is_labeled_absent(self):
        with TemporaryDirectory(prefix='core-agent-harness-') as temporary:
            self.assertIs(process.physical(Path(temporary))['present'], False)

    def test_journal_duplicate_keys_fail(self):
        with TemporaryDirectory(prefix='core-agent-harness-') as temporary:
            directory = Path(temporary)
            (directory / 'task.db').write_text('CORE_TASK_V1\nstatus\tready\nstatus\tcompleted\n')
            with self.assertRaises(AssertionError):
                process.journal(directory)

    def checkpoint_child(self, text):
        directory = TemporaryDirectory(prefix='core-agent-marker-child-')
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / 'marker-child'
        path.write_text('#!/usr/bin/env python3\nimport sys\n' + text)
        path.chmod(0o700)
        original = process.BINARY
        process.BINARY = path
        self.addCleanup(setattr, process, 'BINARY', original)
        harness = process.AgentProcessTests('test_cancel_before_run_has_zero_calls_and_effects')
        self.addCleanup(harness.doCleanups)
        return harness, Path(directory.name)

    def test_checkpoint_observation_waits_for_actual_notification_then_sigkill(self):
        harness, directory = self.checkpoint_child(
            "print('checkpoint=dispatch', flush=True)\nsys.stdin.readline()\n")
        child = harness.pause(directory, 'dispatch')
        self.assertIsNone(child.poll())
        child.kill()
        child.communicate(timeout=10)
        self.assertEqual(child.returncode, -signal.SIGKILL)

    def test_wrong_checkpoint_and_premature_exit_do_not_count_as_reached(self):
        for source in ["print('checkpoint=effect', flush=True)\nsys.stdin.readline()\n", 'sys.exit(0)\n']:
            harness, directory = self.checkpoint_child(source)
            with self.subTest(source=source), self.assertRaises(AssertionError):
                harness.pause(directory, 'dispatch')
            harness.doCleanups()


if __name__ == '__main__':
    unittest.main(verbosity=2)
