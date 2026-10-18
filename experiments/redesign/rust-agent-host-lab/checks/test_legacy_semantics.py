"""All 144 batch3 rejection controls retained, with source-line/target/semantic positives."""
import hashlib
import unittest
from legacy_precise import CONTRACTS
from legacy_semantics import EXPECTED, accepted


class LegacySemanticsTests(unittest.TestCase):
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
