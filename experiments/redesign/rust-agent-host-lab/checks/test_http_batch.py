import unittest
from full import CASES
from http_batch import contract, classify, inverse


def transcript(component):
    lines = ['Finished `test` profile [unoptimized]']
    for key, group in contract()['components'][component]['groups'].items():
        kind, name = key.split(':', 1)
        lines.append(f'Running tests/{name}.rs (target/debug/deps/test)' if kind == 'integration' else f'Running unittests {name} (target/debug/deps/test)')
        lines.extend(f'test {name} ... ok' for name in group['names'])
        lines.append(f"test result: ok. {len(group['names'])} passed; 0 failed; 0 ignored; 0 measured; 0 filtered out;")
    return '\n'.join(lines)


class HttpBatchTests(unittest.TestCase):
    def test_inverse_requires_precise_test_assertion_not_setup_or_timeout(self):
        text = 'test exact_target ... FAILED\ntest result: FAILED. 0 passed; 1 failed; 0 ignored; 0 measured; 6 filtered out;\nassertion `left == right` failed\n  left: "failed"\n right: "outcome_unknown"\n'
        record = dict(exit_code=101, timed_out=False, forced_owned_group_cleanup=False, live_after_cleanup=[])
        needles = ['left: "failed"', 'right: "outcome_unknown"']
        self.assertTrue(inverse(text, record, 'exact_target', needles))
        for bad in (text.replace('exact_target', 'other'), text.replace('outcome_unknown', 'completed'), 'could not compile\n' + text):
            self.assertFalse(inverse(bad, record, 'exact_target', needles))
        for key, value in [('exit_code', 124), ('timed_out', True), ('forced_owned_group_cleanup', True), ('live_after_cleanup', [12])]:
            self.assertFalse(inverse(text, dict(record, **{key:value}), 'exact_target', needles))

    def test_additive_contract_keeps_every_product_case(self):
        extended = contract()
        self.assertEqual(extended['components']['core']['expected_total'], 115)
        self.assertEqual(extended['components']['host']['expected_total'], 59)
        for component in ('core', 'host', 'plugin'):
            for key, group in CASES['components'][component]['groups'].items():
                self.assertTrue(set(group['names']).issubset(extended['components'][component]['groups'][key]['names']))
        self.assertEqual(extended['mutants'], CASES['mutants'])

    def test_exact_complete_suites_and_every_omission(self):
        for component in ('core', 'host'):
            raw = transcript(component)
            self.assertTrue(classify(component, raw, 0)['accepted'])
            for group in contract()['components'][component]['groups'].values():
                for name in group['names']:
                    self.assertFalse(classify(component, raw.replace(f'test {name} ... ok', ''), 0)['accepted'], name)

    def test_wrong_exit_duplicate_filtered_ignored_and_setup_are_invalid(self):
        for component in ('core', 'host'):
            raw = transcript(component)
            for status in (1, 101, 124, -9):
                self.assertFalse(classify(component, raw, status)['accepted'])
            for bad in (raw + raw, raw.replace('0 filtered out', '1 filtered out'), raw.replace('0 ignored', '1 ignored'), raw.replace('Finished', 'Compiling')):
                self.assertFalse(classify(component, bad, 0)['accepted'])
