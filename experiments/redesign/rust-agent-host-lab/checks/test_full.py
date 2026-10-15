"""Synthetic classifier controls, never DUT GREEN or mutant evidence."""
import copy
import unittest
from full import CASES, mutations, python_suite, rust


def transcript(component):
    lines = ['Finished `test` profile [unoptimized]']
    for key, group in CASES['components'][component]['groups'].items():
        kind, name = key.split(':', 1)
        lines.append(f'Running tests/{name}.rs (target/debug/deps/test)' if kind == 'integration' else f'Running unittests {name} (target/debug/deps/test)')
        lines.extend(f'test {name} ... ok' for name in group['names'])
        lines.append(f"test result: ok. {len(group['names'])} passed; 0 failed; 0 ignored; 0 measured; 0 filtered out;")
    lines.extend(['Running unittests src/main.rs (target/debug/deps/main)', 'test result: ok. 0 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out;', 'Doc-tests crate', 'test result: ok. 0 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out;'])
    return '\n'.join(lines)


class FullTests(unittest.TestCase):
    def test_each_source_inventory_accepts_only_complete_green(self):
        for component, total in [('core', 94), ('plugin', 21), ('host', 20)]:
            result = rust(component, transcript(component), 0)
            self.assertTrue(result['accepted'], component)
            self.assertEqual(result['observed_tests'], total)
        self.assertEqual(rust('core', transcript('core'), 0)['families']['legacy-core'], 88)
        self.assertEqual(rust('core', transcript('core'), 0)['unit_tests'], 4)

    def test_multiple_failed_targets_remain_invalid_full(self):
        raw = transcript('core').replace(' ... ok', ' ... FAILED').replace('test result: ok.', 'test result: FAILED.')
        self.assertFalse(rust('core', raw, 101)['accepted'])
        self.assertFalse(rust('core', raw, 0)['accepted'])

    def test_missing_duplicate_renamed_skip_filter_compile_and_wrong_exit_invalid(self):
        for component in CASES['components']:
            raw = transcript(component)
            first = next(iter(CASES['components'][component]['groups'].values()))['names'][0]
            for bad in [raw.replace(f'test {first} ... ok', ''), raw + raw,
                        raw.replace(first, 'unexpected_name'), raw.replace('0 ignored', '1 ignored'),
                        raw.replace('0 filtered out', '1 filtered out'), raw.replace('Finished', 'Compiling'),
                        raw.replace('0 measured', '1 measured')]:
                self.assertFalse(rust(component, bad, 0)['accepted'])
            self.assertFalse(rust(component, raw, 124)['accepted'])
            self.assertFalse(rust(component, raw, -6)['accepted'])

    def test_python_exact_methods_and_zero_skip(self):
        for suite, names in CASES['python'].items():
            raw = '\n'.join(f'{name} (__main__.Case.{name}) ... ok' for name in names) + f'\nRan {len(names)} tests in 1.0s\n\nOK\n'
            self.assertTrue(python_suite(suite, raw, 0)['accepted'])
            for bad in [raw.replace(names[0], 'test_other'), raw + 'OK (skipped=1)\n', raw.replace('OK', 'FAILED'), raw + raw]:
                self.assertFalse(python_suite(suite, bad, 0)['accepted'])
            self.assertFalse(python_suite(suite, raw, 1)['accepted'])

    def test_mutants_require_all_compiled_semantic_failures_no_timeout_or_signal(self):
        rows = [dict(name=name, compiled=True, killed=True, returncode=101, first_failure='test exact_case ... FAILED') for name in CASES['mutants']]
        rows[-1].update(returncode=1, acknowledged=True, physical_failure=True)
        self.assertTrue(mutations(rows, 0)['accepted'])
        for key, value in [('compiled', False), ('killed', False), ('returncode', 124), ('returncode', -9), ('first_failure', '')]:
            bad = copy.deepcopy(rows); bad[0][key] = value
            self.assertFalse(mutations(bad, 0)['accepted'])
        self.assertFalse(mutations(rows[:-1], 0)['accepted'])
        self.assertFalse(mutations(rows, 1)['accepted'])
        rows[-1]['physical_failure'] = False
        self.assertFalse(mutations(rows, 0)['accepted'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
