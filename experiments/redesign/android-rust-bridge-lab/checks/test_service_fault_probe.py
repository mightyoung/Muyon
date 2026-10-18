"""Python transcript controls only; these do not execute or prove native behavior."""
import unittest
from unittest.mock import patch
import json
from pathlib import Path
import service_fault_probe
from service_fault_probe import ASSERTION, CONTRACT, classify, instrument, replace_once


def transcript(case):
    green = CONTRACT['cases'][case]['observed'] == CONTRACT['cases'][case]['expected']
    lines = ['Finished `release` profile [optimized]', 'Running tests/service_private_fault.rs (target/release/deps/service_private_fault-abc)',
        'test service_private_fault_contract ... ' + ('ok' if green else 'FAILED'),
        'FAULT_RECORDED actual_read=success receipt=RecordedSuccess',
        f"FAULT_OBSERVED {case} terminal={CONTRACT['cases'][case]['observed']}"]
    if case != 'c2_worker_panic':
        lines += ['FAULT_CANCEL turn=2 before_original_poll=true']
    if case == 'c3_failed_ledger':
        lines += ['FAULT_LEDGER error=probe_failed_ledger_io not_diskfull=true']
    if case == 'c2_worker_panic':
        lines += ["thread '<unnamed>' (123) panicked at src/service_controller.rs:1:1:", 'SERVICE_PRIVATE_WORKER_PANIC']
    if not green:
        lines += ["thread 'service_private_fault_contract' panicked at tests/service_private_fault.rs:1:1:", ASSERTION]
    lines += ['test result: ' + ('ok. 1 passed; 0 failed;' if green else 'FAILED. 0 passed; 1 failed;') + ' 0 ignored; 0 measured; 0 filtered out;']
    return '\n'.join(lines) + '\n'


class ServiceFaultControls(unittest.TestCase):
    def test_closed_classifier_rejects_setup_auxiliary_panics_and_wrong_receipts(self):
        for case in CONTRACT['cases']:
            raw = transcript(case); status = 0 if CONTRACT['cases'][case]['observed'] == CONTRACT['cases'][case]['expected'] else 101
            self.assertTrue(classify(case, raw, status)['accepted'])
            self.assertFalse(classify(case, raw, 124)['accepted'])
            for bad in [raw + raw, raw.replace('Finished', 'Compiling'), raw.replace('0 filtered out', '1 filtered out'),
                raw.replace('FAULT_RECORDED actual_read=success receipt=RecordedSuccess\n', ''),
                raw.replace('FAULT_OBSERVED', 'OTHER_OBSERVED'), raw.replace('opaque_match=', 'opaque_other='),
                raw + "thread 'aux' (1) panicked at src/other.rs:1:1:\nextra\n",
                raw + 'error[E0001]: bad\n', raw + 'No space left on device\n',
                raw.replace('service_private_fault.rs (', 'wrong_target.rs (')]:
                self.assertFalse(classify(case, bad, status)['accepted'], (case, bad))
            self.assertFalse(classify(case, raw.replace('RecordedSuccess', 'Unknown'), status)['accepted'])

    def test_separate_c2_green_keeps_real_worker_panic_required(self):
        green = json.loads(Path(service_fault_probe.__file__).with_name('service_fault_c2_green_cases.json').read_text())
        raw = transcript('c2_worker_panic')
        raw = raw.replace(CONTRACT['cases']['c2_worker_panic']['observed'], green['cases']['c2_worker_panic']['observed'])
        raw = raw.replace('test service_private_fault_contract ... FAILED', 'test service_private_fault_contract ... ok')
        raw = raw.replace("thread 'service_private_fault_contract' panicked at tests/service_private_fault.rs:1:1:\n" + ASSERTION + '\n', '')
        raw = raw.replace('FAILED. 0 passed; 1 failed;', 'ok. 1 passed; 0 failed;')
        with patch.object(service_fault_probe, 'CONTRACT', green):
            self.assertTrue(classify('c2_worker_panic', raw, 0)['accepted'])
            self.assertFalse(classify('c2_worker_panic', raw.replace('SERVICE_PRIVATE_WORKER_PANIC', 'other'), 0)['accepted'])
            self.assertFalse(classify('c2_worker_panic', raw, 101)['accepted'])

    def test_lease_red_requires_completed_worker_cross_process_gap(self):
        red = json.loads(Path(service_fault_probe.__file__).with_name('service_fault_c2_lease_red_cases.json').read_text())
        raw = transcript('c2_worker_panic')
        raw = raw.replace('FAULT_OBSERVED c2_worker_panic terminal=' + CONTRACT['cases']['c2_worker_panic']['observed'], 'FAULT_LEASE worker_finished_before_join=available')
        raw = raw.replace(ASSERTION, 'SERVICE_PRIVATE_LEASE_RED: worker completion retains original root until Closed')
        with patch.object(service_fault_probe, 'CONTRACT', red):
            self.assertTrue(classify('c2_worker_panic', raw, 101)['accepted'])
            self.assertFalse(classify('c2_worker_panic', raw.replace('before_join=available', 'before_join=busy'), 101)['accepted'])
            self.assertFalse(classify('c2_worker_panic', raw + 'FAULT_LEASE after_closed=available\n', 101)['accepted'])

    def test_deadline_late_cancel_red_requires_original_real_stop_and_reason(self):
        deadline = json.loads(Path(service_fault_probe.__file__).with_name('service_deadline_red_cases.json').read_text())
        case = 'c3_deadline_late_cancel'
        raw = transcript('c3_cancel')
        raw = raw.replace('FAULT_OBSERVED c3_cancel terminal=' + CONTRACT['cases']['c3_cancel']['observed'],
            'FAULT_OBSERVED ' + case + ' terminal=' + deadline['cases'][case]['observed'])
        raw = raw.replace('FAULT_CANCEL turn=2 before_original_poll=true',
            'FAULT_DEADLINE actual_poll=expired\nFAULT_DEADLINE original_stop=host_budget deadline_poll=true late_cancel=true')
        raw = raw.replace(ASSERTION, deadline['cases'][case]['assertion'])
        with patch.object(service_fault_probe, 'CONTRACT', deadline):
            self.assertTrue(classify(case, raw, 101)['accepted'])
            for bad in [raw.replace('actual_poll=expired', 'actual_poll=unknown'), raw.replace('reason=BudgetExceeded', 'reason=DeadlineExceeded'), raw.replace('late_cancel=true', 'late_cancel=false')]:
                self.assertFalse(classify(case, bad, 101)['accepted'])

    def test_unique_anchors_and_hashes_fail_closed(self):
        self.assertEqual(replace_once('abc', 'b', 'X'), 'aXc')
        for source in ['', 'bb']:
            with self.assertRaisesRegex(RuntimeError, 'anchor_invalid'):
                replace_once(source, 'b', 'X')
        with self.assertRaisesRegex(RuntimeError, 'source_invalid'):
            instrument({name: b'wrong' for name in CONTRACT['source_sha256']}, 'c2_worker_panic')
        with self.assertRaisesRegex(RuntimeError, 'case_invalid'):
            instrument({}, 'other')


if __name__ == '__main__':
    unittest.main()
