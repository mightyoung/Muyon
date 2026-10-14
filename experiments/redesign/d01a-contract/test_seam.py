"""Tests specify the seam's semantics; no fixture expected enters the DUT."""
import copy
import unittest
from seam import decide
from fixture_adapter import to_stimulus


def evidence(purpose='local_supplier_name_write', mode='FullAllow'):
    return {
        'purpose': {'current': purpose, 'required_units': ['u'], 'actual_range': ['u']},
        'source_inheritance': {'unit_ref': 'u', 'source_kind': 'model_generated',
            'trusted_event_ref': 'host-event', 'source_version': 'sv1', 'source_rights': 'valid_assumption',
            'field_path': 'supplier.name', 'trusted_field_base': 'none', 'field_declaration_version': 'decl-v1',
            'inherited_sensitivity_units': [], 'inherited_purpose_restrictions': []},
        'current_version': {'normalized': 'nv1', 'checked': 'nv1', 'final': 'nv1', 'evidence_current': True},
        'rule_coverage': [{'rule_id': rule, 'assumed_current_purpose_coverage': 'complete',
            'assumed_covered_units': ['u']} for rule in ['CLS-DECL-001', 'CLS-MODEL-FIELD-001', 'CLS-CREDENTIAL-001', 'CLS-PURPOSE-001']],
        'actual_value_check': {'target_ref': 'nv1', 'target_is_actual_new_value': True,
            'state': 'complete_assumption', 'signal': 'none_assumption'},
        'mode_facts': {'mode': mode, 'mode_grant': 'valid_finite_synthetic_assumption',
            'grant_created_at': '2026-10-14T00:00:00Z', 'expires_at': '2026-10-14T00:10:00Z',
            'evaluated_at': '2026-10-14T00:01:00Z', 'auto_risk_rule': 'unfrozen_not_required_by_FullAllow', 'risk': 'high'},
        'execution_prerequisites': {x: 'valid_assumption' for x in ['scope', 'read_right', 'write_right', 'identity', 'capability', 'plan_revision', 'cas', 'business_validity', 'ledger']},
        'input': {'clean_text': '合成名字', 'complete_single_field': True},
    }


class AdmissionTests(unittest.TestCase):
    def result(self, value):
        result = decide(value)
        self.assertIsNotNone(result, 'admission/routing seam has not been implemented')
        return result

    def test_covered_generated_field_has_current_purpose_material_eligibility(self):
        result = self.result(evidence())
        self.assertEqual(result['material']['state'], 'eligible')
        self.assertEqual(result['sensitivity_context'], 'none')
        self.assertEqual(result['material']['noncurrent'], 'not_applicable')
        self.assertFalse(result['dispatch_performed'])

    def test_none_field_does_not_replace_actual_value_check(self):
        value = evidence(); value['actual_value_check']['state'] = 'not_executed_assumption'
        result = self.result(value)
        self.assertEqual(result['material']['state'], 'blocked_contract')
        self.assertNotEqual(result['route']['state'], 'eligible')

    def test_actual_generated_value_requires_trusted_field_declaration(self):
        value = evidence(); value['source_inheritance']['field_declaration_version'] = None
        self.assertEqual(self.result(value)['material']['state'], 'ineligible')

    def test_unknown_field_fails_closed(self):
        value = evidence(); value['source_inheritance']['field_path'] = 'supplier.name_alias'
        self.assertEqual(self.result(value)['material']['state'], 'ineligible')

    def test_stale_normalized_target_is_not_current_value_evidence(self):
        value = evidence(); value['current_version']['final'] = 'nv2'
        result = self.result(value)
        self.assertEqual(result['material']['state'], 'ineligible')
        self.assertTrue(result['attempt_terminal'])

    def test_none_target_does_not_downgrade_commercial_source(self):
        value = evidence(); value['source_inheritance']['inherited_sensitivity_units'] = [{'sensitivity': 'commercial'}]
        self.assertEqual(self.result(value)['sensitivity_context'], 'commercial')

    def test_source_purpose_prohibition_is_not_overridden_by_FullAllow(self):
        value = evidence(); value['source_inheritance']['inherited_purpose_restrictions'] = ['current purpose forbidden']
        self.assertEqual(self.result(value)['material']['state'], 'ineligible')

    def test_credential_signal_blocks_every_current_body_purpose(self):
        for purpose in ['local_supplier_name_write', 'model_request', 'business_outbound']:
            with self.subTest(purpose=purpose):
                value = evidence(purpose); value['actual_value_check']['signal'] = 'known_hit_assumption'
                self.assertEqual(self.result(value)['material']['state'], 'ineligible')

    def test_outbound_unreviewed_no_coverage_ends_attempt(self):
        value = evidence('business_outbound'); value['rule_coverage'][1]['assumed_current_purpose_coverage'] = 'none'
        result = self.result(value)
        self.assertEqual(result['sensitivity_context'], 'unreviewed')
        self.assertEqual(result['attempt'], 'no_coverage')
        self.assertTrue(result['attempt_terminal'])

    def test_pure_local_user_value_does_not_wait_for_global_output_rules(self):
        value = evidence(); value['source_inheritance']['source_kind'] = 'user_input'
        value['rule_coverage'] = [x for x in value['rule_coverage'] if x['rule_id'] != 'CLS-MODEL-FIELD-001']
        value['current_version']['global_outbound_classification_coverage'] = 'uncovered_not_a_local_gate'
        self.assertEqual(self.result(value)['material']['state'], 'eligible')

    def test_FullAllow_missing_Auto_rule_is_not_a_contract_block(self):
        self.assertEqual(self.result(evidence())['route']['state'], 'eligible')

    def test_Auto_unfrozen_rule_blocks_route_without_changing_material(self):
        value = evidence(mode='Auto')
        result = self.result(value)
        self.assertEqual(result['material']['state'], 'eligible')
        self.assertEqual(result['route']['state'], 'blocked_contract')

    def test_Auto_high_requires_current_intent_confirmation(self):
        value = evidence(mode='Auto'); value['mode_facts']['auto_risk_rule'] = 'synthetic_frozen_assumption_for_routing_only'
        self.assertEqual(self.result(value)['route']['state'], 'await_confirmation')

    def test_Auto_low_can_route_under_assumed_frozen_rule(self):
        value = evidence(mode='Auto'); value['mode_facts'].update(auto_risk_rule='synthetic_frozen_assumption_for_routing_only', risk='low')
        self.assertEqual(self.result(value)['route']['state'], 'eligible')

    def test_hard_CAS_constraint_blocks_route_in_FullAllow(self):
        value = evidence(); value['execution_prerequisites']['cas'] = 'revision_changed'
        result = self.result(value)
        self.assertEqual(result['material']['state'], 'eligible')
        self.assertEqual(result['route']['state'], 'rejected')

    def test_readOnly_write_blocks_route_but_not_content(self):
        result = self.result(evidence(mode='readOnly'))
        self.assertEqual(result['material']['state'], 'eligible')
        self.assertEqual(result['route']['state'], 'rejected')

    def test_expired_mode_capability_is_not_current_authorization(self):
        value = evidence(); value['mode_facts']['evaluated_at'] = value['mode_facts']['expires_at']
        self.assertEqual(self.result(value)['route']['state'], 'rejected')

    def test_missing_page_actual_check_blocks_current_purpose(self):
        value = evidence('model_request'); value['purpose']['required_units'] = ['u', 'page.8']
        self.assertEqual(self.result(value)['material']['state'], 'blocked_contract')

    def test_missing_or_unrecognized_source_kind_is_not_user_input(self):
        for kind in [None, 'unknown_future_provider', 'unreviewed_as_source']:
            with self.subTest(kind=kind):
                value = evidence(); value['source_inheritance']['source_kind'] = kind
                self.assertEqual(self.result(value)['material']['state'], 'ineligible')

    def test_known_derived_and_template_sources_need_their_current_rules(self):
        for kind in ['derived', 'host_template']:
            with self.subTest(kind=kind):
                value = evidence(); value['source_inheritance']['source_kind'] = kind
                self.assertEqual(self.result(value)['material']['state'], 'blocked_contract')

    def test_readOnly_model_needs_independent_authorization_not_a_write_ban(self):
        value = evidence('model_request', mode='readOnly')
        self.assertEqual(self.result(value)['route']['state'], 'blocked_contract')

    def test_unknown_inherited_sensitivity_cannot_be_washed_into_none(self):
        value = evidence(); value['source_inheritance']['inherited_sensitivity_units'] = [{'sensitivity': 'unknown_future_category'}]
        self.assertEqual(self.result(value)['material']['state'], 'ineligible')

    def test_missing_source_version_is_not_current_source_evidence(self):
        value = evidence(); value['source_inheritance']['source_version'] = None
        self.assertEqual(self.result(value)['material']['state'], 'ineligible')

    def test_uninterpreted_source_restriction_is_not_an_implicit_permission(self):
        value = evidence(); value['source_inheritance']['inherited_purpose_restrictions'] = ['unknown-policy-clause']
        self.assertEqual(self.result(value)['material']['state'], 'blocked_contract')

    def test_DUT_rejects_expected_or_case_identity_even_when_valid_input(self):
        for key in ['expected', 'case_id', 'variant_id']:
            with self.subTest(key=key):
                value = evidence(); value[key] = {'material': 'eligible'}
                with self.assertRaises(ValueError): decide(value)


class AdapterTests(unittest.TestCase):
    def test_adapter_strips_oracle_fields_without_reading_them(self):
        source = evidence(); source.update(expected={'poison': True}, case_id='poison', variant_id='poison')
        result = to_stimulus(source)
        self.assertIsInstance(result, dict, 'fixture adapter has not been implemented')
        self.assertNotIn('expected', result); self.assertNotIn('case_id', result); self.assertNotIn('variant_id', result)
        self.assertEqual(result, evidence())
        result['actual_value_check']['signal'] = 'changed'
        self.assertEqual(source['actual_value_check']['signal'], 'none_assumption')


if __name__ == '__main__': unittest.main()
