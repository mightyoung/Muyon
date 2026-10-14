import copy
import unittest
from driver import compare_variant, purpose_oracle
from fixture_adapter import to_stimulus
from seam import decide
from test_seam import evidence


def variant():
    value = evidence()
    value.update(variant_id='not_dut_input', expected={
        'local_body_allowed': True, 'model_body_allowed': True,
        'business_outbound_allowed': True,
        'action_result': 'eligible_under_fixture_assumptions_not_executed'})
    return value


class DriverTests(unittest.TestCase):
    def test_expected_and_identity_never_enter_DUT(self):
        def checked_dut(stimulus):
            self.assertNotIn('expected', stimulus)
            self.assertNotIn('variant_id', stimulus)
            self.assertNotIn('case_id', stimulus)
            return decide(stimulus)
        compared = compare_variant(variant(), checked_dut)
        self.assertIsNotNone(compared, 'fixture comparison driver not implemented')
        self.assertEqual(compared['mismatches'], [])

    def test_expected_access_occurs_after_DUT_invocation(self):
        called = []
        class Guarded(dict):
            def __getitem__(self, key):
                if key == 'expected' and not called:
                    raise AssertionError('oracle accessed before DUT')
                return super().__getitem__(key)
        def tracked(stimulus):
            actual = decide(stimulus)
            called.append(True)
            return actual
        compared = compare_variant(Guarded(variant()), tracked)
        self.assertIsNotNone(compared, 'fixture comparison driver not implemented')
        self.assertTrue(called)
        self.assertEqual(compared['mismatches'], [])

    def test_wrong_expected_is_detected_without_changing_DUT_result(self):
        clean = variant(); poison = copy.deepcopy(clean)
        poison['expected']['local_body_allowed'] = False
        a = compare_variant(clean); b = compare_variant(poison)
        self.assertIsNotNone(a, 'fixture comparison driver not implemented')
        self.assertIsNotNone(b, 'fixture comparison driver not implemented')
        self.assertEqual(a['actual'], b['actual'])
        self.assertEqual(a['mismatches'], [])
        self.assertIn('current_purpose_material', b['mismatches'])

    def test_case_identity_does_not_change_result(self):
        a = variant(); b = copy.deepcopy(a)
        a['case_id'] = 'A'; b['case_id'] = 'B'; b['variant_id'] = 'changed'
        x = compare_variant(a); y = compare_variant(b)
        self.assertIsNotNone(x, 'fixture comparison driver not implemented')
        self.assertEqual(x['actual'], y['actual'])

    def test_I03_projection_never_reads_noncurrent_true_as_grant(self):
        value = variant(); value['expected']['model_body_allowed'] = False
        projected = purpose_oracle(value)
        self.assertIsNotNone(projected, 'current-purpose oracle projection not implemented')
        self.assertEqual(projected, {'purpose': 'local_supplier_name_write', 'eligible': True,
                                     'noncurrent': 'not_applicable'})

    def test_adapter_rejects_nested_oracle_in_supplied_sections(self):
        value = variant(); value['input']['expected'] = {'poison': True}
        with self.assertRaises(ValueError): decide(to_stimulus(value))


if __name__ == '__main__': unittest.main()
