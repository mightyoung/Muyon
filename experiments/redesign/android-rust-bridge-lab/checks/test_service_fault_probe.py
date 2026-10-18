"""Python transcript controls only; these do not execute or prove native behavior."""
import unittest
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
