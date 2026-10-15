"""Synthetic checker controls only; not Rust DUT RED evidence."""
import unittest

from red import CONTRACTS, classify


def transcript(suite):
    c = CONTRACTS[suite]
    return (f'Finished `test` profile [unoptimized]\n'
            f'Running tests/{c["target"]}.rs (target/debug/deps/test)\n'
            'running 1 test\n' + c['reach'] + '\n'
            f'thread \'{c["test"]}\' panicked at tests/{c["target"]}.rs:10:5:\n'
            + c['assertion'] + '\n  left: 0\n right: 1\n'
            f'test {c["test"]} ... FAILED\n'
            f'test result: FAILED. 0 passed; 1 failed; 0 ignored; 0 measured; {c["filtered"]} filtered out;\n')


class RedTests(unittest.TestCase):
    def test_host_core_stub_or_setup_guard_cannot_replace_reached_host_dispatch(self):
        self.assertEqual(CONTRACTS['host-red']['filtered'], 16)
        raw = transcript('host-red')
        wrong = raw.replace(CONTRACTS['host-red']['reach'], 'NATIVE_PORT_STUB_REACHED persists=1 dispatches=0')
        self.assertFalse(classify('host-red', wrong, 101)['accepted'])
        wrong = raw.replace(CONTRACTS['host-red']['assertion'], 'real common drive must reach native dispatch before interpreting RED')
        self.assertFalse(classify('host-red', wrong, 101)['accepted'])
        self.assertFalse(classify('host-red', raw.replace('16 filtered out', '12 filtered out'), 101)['accepted'])

    def test_protocol_four_case_contract_rejects_old_filtered_count(self):
        self.assertEqual(CONTRACTS['protocol-red']['filtered'], 3)
        old = transcript('protocol-red').replace('3 filtered out', '2 filtered out')
        self.assertFalse(classify('protocol-red', old, 101)['accepted'])

    def test_each_exact_guard_and_assertion_is_recognized(self):
        for suite in CONTRACTS:
            self.assertTrue(classify(suite, transcript(suite), 101)['accepted'])

    def test_compilation_setup_timeout_and_wrong_exit_are_not_red(self):
        for suite in CONTRACTS:
            raw = transcript(suite)
            for text, code in [(raw, 0), (raw, 124), ('compile error', 101),
                               (raw.replace('Finished', 'Compiling'), 101),
                               (raw + 'TimeoutException', 101)]:
                self.assertFalse(classify(suite, text, code)['accepted'])

    def test_missing_wrong_or_late_reach_guard_is_not_red(self):
        for suite, contract in CONTRACTS.items():
            raw = transcript(suite)
            for text in [raw.replace(contract['reach'], ''),
                         raw.replace(contract['reach'], '') + contract['reach'],
                         raw.replace(contract['reach'], 'UNRELATED_STUB_REACHED')]:
                self.assertFalse(classify(suite, text, 101)['accepted'])

    def test_wrong_target_marker_extra_failure_and_skip_are_not_red(self):
        for suite, contract in CONTRACTS.items():
            raw = transcript(suite)
            for text in [raw.replace(contract['test'], 'other_test'),
                         raw.replace(contract['assertion'], 'wrong assertion') + contract['assertion'],
                         raw + 'test extra ... FAILED\n',
                         raw.replace('0 ignored', '1 ignored'),
                         raw.replace(f'{contract["filtered"]} filtered out', '99 filtered out')]:
                self.assertFalse(classify(suite, text, 101)['accepted'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
