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
        for component, total in [('core', 94), ('plugin', 21), ('host', 29)]:
            result = rust(component, transcript(component), 0)
            self.assertTrue(result['accepted'], component)
            self.assertEqual(result['observed_tests'], total)
        self.assertEqual(rust('core', transcript('core'), 0)['families']['legacy-core'], 88)
        self.assertEqual(rust('core', transcript('core'), 0)['unit_tests'], 4)

    def test_source_fixed_service_group_preserves_native_twenty_five(self):
        result = rust('host', transcript('host'), 0)
        self.assertEqual(result['families'], {'native-host': 25, 'service-controller': 4})
        service = CASES['components']['host']['groups'].get('integration:service_controller')
        self.assertIsNotNone(service, 'separate source-fixed service integration group is missing')
        self.assertEqual(service['names'], [
            'service_controller_executes_registered_read',
            'controller_is_send_sync_without_moving_native_session',
            'build_identity_is_explicit_without_host_build_environment',
            'zero_client_initialization_retirement_requires_real_settlement',
        ])
        raw = transcript('host')
        for name in service['names']:
            self.assertFalse(rust('host', raw.replace(f'test {name} ... ok', ''), 0)['accepted'])

    def test_host_twenty_five_rejects_previous_twenty_and_missing_safety_case(self):
        added = {
            'missing_selected_refs_execute_zero_before_physical_read',
            'revoke_after_preinvoke_snapshot_executes_zero',
            'native_store_restore_rejects_forged_receipts_and_facts',
            'native_store_persist_budget_never_writes_unreadable_snapshot',
            'cancel_during_handler_retains_raw_receipt_without_projection',
        }
        raw = transcript('host')
        for name in added:
            self.assertFalse(rust('host', raw.replace(f'test {name} ... ok', ''), 0)['accepted'])
        old = raw
        for name in added:
            old = old.replace(f'test {name} ... ok\n', '')
        old = old.replace('25 passed', '20 passed')
        self.assertFalse(rust('host', old, 0)['accepted'])

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
