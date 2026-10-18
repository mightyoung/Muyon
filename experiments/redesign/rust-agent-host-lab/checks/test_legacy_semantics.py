"""All 144 batch3 rejection controls retained, with source-line/target/semantic positives."""
import hashlib
import unittest
from legacy_precise import CONTRACTS
from legacy_semantics import EXPECTED, accepted


class LegacySemanticsTests(unittest.TestCase):
    def test_pre_timing_fix_wire_source_locations_are_rejected(self):
        old_locations = {
            'wire_stale_reported_usage': 'wire.rs:182:306',
            'wire_private_history_bound': 'wire.rs:88:180',
            'wire_stream_cancel_bypass': 'wire.rs:122:161',
            'wire_native_pair': 'wire.rs:173:1005',
            'wire_budget_bypass': 'wire.rs:106:184',
        }
        targets = {name: test for name, _, test, _ in CONTRACTS}
        for name, location in old_locations.items():
            test = targets[name]
            _, *needles = EXPECTED[name]
            text = (f"thread '{test}' panicked at tests/{location}:\n" + '\n'.join(needles)
                    + f'\ntest {test} ... FAILED\ntest result: FAILED. 0 passed; 1 failed; 0 ignored; 0 measured; 9 filtered out;\n')
            record = dict(exit_code=101, timed_out=False, forced_owned_group_cleanup=False,
                          live_after_cleanup=[], raw_sha256=hashlib.sha256(text.encode()).hexdigest())
            self.assertFalse(accepted(dict(name=name, test=test, baseline_green=True), text, record), name)

    def test_exact_assertions_and_all_144_negative_controls(self):
        controls = 0
        for name, target, test, _ in CONTRACTS:
            location, *needles = EXPECTED[name]
            row = dict(name=name, test=test, baseline_green=True)
            text = (f"thread '{test}' panicked at tests/{location}:\n" + '\n'.join(needles)
                    + f'\ntest {test} ... FAILED\ntest result: FAILED. 0 passed; 1 failed; 0 ignored; 0 measured; 9 filtered out;\n')
            record = dict(exit_code=101, timed_out=False, forced_owned_group_cleanup=False,
                          live_after_cleanup=[], raw_sha256=hashlib.sha256(text.encode()).hexdigest())
            self.assertTrue(accepted(row, text, record), name)
            for key, value in [('exit_code', 0), ('exit_code', 124), ('timed_out', True),
                               ('forced_owned_group_cleanup', True), ('live_after_cleanup', [1])]:
                self.assertFalse(accepted(row, text, dict(record, **{key: value})), name)
                controls += 1
            for bad in ['could not compile\n' + text, text.replace('tests/' + location, 'tests/wrong.rs:1:1'),
                        text.replace(test, 'wrong_target'), text.replace(needles[0], 'WRONG_ASSERTION')]:
                changed = dict(record, raw_sha256=hashlib.sha256(bad.encode()).hexdigest())
                self.assertFalse(accepted(row, bad, changed), name)
                controls += 1
        self.assertEqual(controls, 144)


if __name__ == '__main__':
    unittest.main(verbosity=2)
