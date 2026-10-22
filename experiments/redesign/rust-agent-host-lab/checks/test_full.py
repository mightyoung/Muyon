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
        for component, total in [('core', 107), ('plugin', 22), ('host', 48)]:
            result = rust(component, transcript(component), 0)
            self.assertTrue(result['accepted'], component)
            self.assertEqual(result['observed_tests'], total)
        self.assertEqual(rust('core', transcript('core'), 0)['families']['legacy-core'], 90)
        self.assertEqual(rust('core', transcript('core'), 0)['unit_tests'], 6)

    def test_host_stop_cause_units_are_additive_and_old_46_is_invalid(self):
        group = CASES['components']['host']['groups']['unit:src/lib.rs']
        self.assertEqual(group['family'], 'service-stop-cause')
        self.assertEqual(group['names'], [
            'service_runtime::stop_cause_tests::observed_deadline_survives_late_cancel',
            'service_runtime::stop_cause_tests::observed_cancel_survives_later_deadline',
        ])
        raw = transcript('host')
        self.assertEqual(rust('host', raw, 0)['unit_tests'], 2)
        for name in group['names']:
            self.assertFalse(rust('host', raw.replace(f'test {name} ... ok', ''), 0)['accepted'])
        old = raw
        for name in group['names']:
            old = old.replace(f'test {name} ... ok\n', '')
        old = old.replace('2 passed', '0 passed')
        self.assertFalse(rust('host', old, 0)['accepted'])
        self.assertEqual(len(CASES['mutants']), 17)

    def test_core_lock_units_are_required_without_replacing_http_or_old_cases(self):
        names = CASES['components']['core']['groups']['unit:src/lib.rs']['names']
        required = {'store::lock_tests::guard_drop_releases_lock_while_same_open_file_description_survives',
                    'store::lock_tests::live_guard_excludes_independent_open_until_explicit_owner_drop'}
        self.assertTrue(required.issubset(names))
        raw = transcript('core')
        for name in required:
            self.assertFalse(rust('core', raw.replace(f'test {name} ... ok', ''), 0)['accepted'])
        self.assertEqual(len(CASES['components']['core']['groups']['integration:http_transport']['names']), 11)

    def test_new_transport_and_registration_are_additive_required_groups(self):
        core = CASES['components']['core']['groups']['integration:http_transport']
        self.assertEqual(core['family'], 'synthetic-http-transport')
        self.assertEqual(len(core['names']), 11)
        self.assertEqual(rust('core', transcript('core'), 0)['families']['synthetic-http-transport'], 11)
        registration = CASES['components']['plugin']['groups']['integration:registration']['names']
        self.assertEqual(len(registration), 9)
        self.assertIn('foreign_data_admission_requires_the_referenced_schema_closure', registration)
        for component, names in [('core', core['names']), ('plugin', registration), ('host', CASES['components']['host']['groups']['integration:service_lifecycle']['names'])]:
            raw = transcript(component)
            for name in names:
                self.assertFalse(rust(component, raw.replace(f'test {name} ... ok', ''), 0)['accepted'])

    def test_source_fixed_service_group_preserves_native_twenty_five(self):
        result = rust('host', transcript('host'), 0)
        self.assertEqual(result['families'], {'native-host': 25, 'service-controller': 4, 'contract-transport': 8, 'service-runtime': 2, 'service-root': 2, 'service-oracle': 1, 'service-lifecycle': 4, 'service-stop-cause': 2})
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

    def test_source_fixed_transport_group_cannot_replace_existing_families(self):
        transport = CASES['components']['host']['groups'].get('integration:contract_transport')
        self.assertIsNotNone(transport, 'separate source-fixed transport group is missing')
        self.assertEqual(transport['names'], [
            'persistent_catalog_keeps_generation_and_one_shot_ticket',
            'tickets_cannot_cross_catalog_instances',
            'recoverable_schema_rejection_preserves_catalog',
            'fatal_envelope_replies_latch_transport_closed',
            'raw_frames_enforce_utf8_duplicates_depth_and_limits',
            'explicit_transport_close_rejects_future_inspection',
            'wire_close_retains_child_command_inspection_semantics',
            'embedded_line_feed_is_fatal_but_crlf_sibling_is_valid',
        ])
        raw = transcript('host')
        for name in transport['names']:
            self.assertFalse(rust('host', raw.replace(f'test {name} ... ok', ''), 0)['accepted'])

    def test_runtime_and_root_are_separate_source_fixed_groups(self):
        expected = {
            'service_runtime': ['all_builtins_read_physical_file_and_journal_two_actual_payloads',
                                'pre_cancelled_worker_never_bootstraps_or_reads'],
            'service_oracle': ['service_controller_observer_correlates_all_builtin_payloads'],
            'service_lifecycle': ['client_epochs_generations_and_visibility_are_fail_closed',
                                  'same_request_is_existing_without_a_second_worker',
                                  'close_and_reconnect_preserve_original_durable_outcome', 'incomplete_temp_evidence_blocks_ready_without_cleanup'],
            'service_root': ['root_lease_serializes_durable_admission_and_preserves_identity',
                             'root_inventory_refuses_unowned_entries_and_peak_overflow'],
        }
        for target, names in expected.items():
            group = CASES['components']['host']['groups'].get('integration:' + target)
            self.assertIsNotNone(group)
            self.assertEqual(group['names'], names)
            for name in names:
                self.assertFalse(rust('host', transcript('host').replace(f'test {name} ... ok', ''), 0)['accepted'])

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
