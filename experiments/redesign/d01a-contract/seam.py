"""Experimental admission of host-evidence assumptions, never a credential scanner.

No fixture file, expected output, identity, product DTO, transport, DB or model is
read here. This computes a current-purpose material decision and a separate
policy route; no capability is issued, consumed or dispatched.
"""
from datetime import datetime

FORBIDDEN_KEYS = {'expected', 'case_id', 'variant_id'}
PURPOSES = {'local_supplier_name_write', 'model_request', 'business_outbound'}
SENSITIVITIES = {'unreviewed', 'none', 'personal', 'commercial', 'credential'}


def reject_oracle(value):
    if isinstance(value, dict):
        if FORBIDDEN_KEYS.intersection(value):
            raise ValueError('oracle/fixture identity is not DUT stimulus')
        for item in value.values():
            reject_oracle(item)
    elif isinstance(value, list):
        for item in value:
            reject_oracle(item)


def result(purpose, material, route, sensitivity='unreviewed', attempt='complete', reason=''):
    return {'material': {'purpose': purpose, 'state': material, 'noncurrent': 'not_applicable'},
            'route': {'state': route, 'reason': reason}, 'sensitivity_context': sensitivity,
            'attempt': attempt, 'attempt_terminal': True, 'dispatch_performed': False,
            'status': 'not_run' if material == 'not_run' else 'partial_experimental',
            'coverage': 'admission/routing of supplied host assumptions; not actual classification/scanning'}


def decide(stimulus):
    reject_oracle(stimulus)
    purpose = stimulus.get('purpose', {}).get('current')
    if purpose not in PURPOSES:
        return result(purpose, 'not_run', 'not_run', reason='unsupported_current_purpose')
    data = stimulus.get('input', {})
    # These need transform/template/recovery facts that the v1 inputs do not supply.
    if data.get('transform') or data.get('retention_policy') or data.get('previously_used_version'):
        return result(purpose, 'not_run', 'not_run', reason='transform_or_retention_execution_evidence_not_supplied')
    if data.get('previous_attempt') or 'same_intent_replay' in data.get('mutations', []):
        return result(purpose, 'not_run', 'not_run', reason='new_attempt_or_authoritative_replay_evidence_not_supplied')
    if data.get('template_version'):
        return result(purpose, 'not_run', 'not_run', reason='trusted_template_registry_not_supplied')

    source = stimulus.get('source_inheritance', {})
    check = stimulus.get('actual_value_check', {})
    versions = stimulus.get('current_version', {})
    sensitivity = source.get('trusted_field_base')
    if sensitivity not in SENSITIVITIES:
        sensitivity = 'unreviewed'
    inherited = [x.get('sensitivity') for x in source.get('inherited_sensitivity_units', [])]
    if any(category not in SENSITIVITIES for category in inherited):
        return result(purpose, 'ineligible', 'rejected', 'unreviewed', 'no_coverage',
                      'unknown_inherited_sensitivity')
    # Keep all restrictions in the input. A single context label never washes lineage.
    for category in ['personal', 'commercial', 'unreviewed', 'credential']:
        if category in inherited:
            sensitivity = category
    signal = check.get('signal')
    if signal == 'known_hit_assumption' or sensitivity == 'credential':
        return result(purpose, 'ineligible', 'rejected', 'credential', reason='credential_body_prohibited')
    if signal == 'suspected_assumption':
        return result(purpose, 'ineligible', 'rejected', 'unreviewed', 'incomplete', 'suspected_credential')
    if not source.get('trusted_event_ref') or not source.get('source_version') or source.get('source_kind') not in {
            'user_input', 'model_generated', 'tool_result', 'user_selected_attachment',
            'source_metadata', 'host_template', 'derived'}:
        return result(purpose, 'ineligible', 'rejected', sensitivity, 'incomplete', 'trusted_source_proof_missing')
    if source.get('source_rights') != 'valid_assumption':
        return result(purpose, 'ineligible', 'rejected', sensitivity, 'invalidated', 'source_rights_unavailable')
    restrictions = source.get('inherited_purpose_restrictions', [])
    if 'current purpose forbidden' in restrictions:
        return result(purpose, 'ineligible', 'rejected', sensitivity, reason='current_source_purpose_forbidden')
    if any(clause != 'only current permitted synthetic task' for clause in restrictions):
        return result(purpose, 'blocked_contract', 'blocked_contract', sensitivity, 'no_coverage',
                      'source_purpose_restriction_contract_unknown')

    field = source.get('field_path')
    if field:
        if field != 'supplier.name':
            if field.startswith('supplier.'):
                return result(purpose, 'ineligible', 'rejected', 'unreviewed', 'no_coverage', 'unknown_field')
            return result(purpose, 'not_run', 'not_run', reason='non_supplier_field_registry_not_supplied')
        if not source.get('field_declaration_version') or source.get('trusted_field_base') not in SENSITIVITIES:
            return result(purpose, 'ineligible', 'rejected', 'unreviewed', 'no_coverage', 'trusted_field_declaration_missing')

    if not versions.get('evidence_current'):
        return result(purpose, 'ineligible', 'rejected', 'unreviewed', 'invalidated', 'stale_content_evidence')
    required = set(stimulus.get('purpose', {}).get('required_units', []))
    coverage = {item['rule_id']: item for item in stimulus.get('rule_coverage', [])}
    needed = {'CLS-CREDENTIAL-001', 'CLS-PURPOSE-001'}
    if field:
        needed.add('CLS-DECL-001')
    if source.get('source_kind') == 'model_generated':
        needed.add('CLS-MODEL-FIELD-001' if field else 'CLS-MODEL-FREE-001')
    if source.get('source_kind') == 'tool_result':
        needed.add('CLS-PROVIDER-001')
    if source.get('source_kind') == 'user_selected_attachment':
        needed.add('CLS-ATTACH-001')
    if source.get('source_kind') == 'derived':
        needed.add('CLS-DERIVE-001')
    if source.get('source_kind') == 'host_template':
        needed.add('CLS-TEMPLATE-001')
    if source.get('source_kind') == 'source_metadata':
        needed.add('CLS-METADATA-001')
    if source.get('source_kind') == 'user_input' and not field:
        needed.add('USER-TEXT-v1')
    if not required or any(rule not in coverage or
                          coverage[rule].get('assumed_current_purpose_coverage') != 'complete' or
                          not required.issubset(set(coverage[rule].get('assumed_covered_units', [])))
                          for rule in needed):
        return result(purpose, 'blocked_contract', 'blocked_contract', 'unreviewed', 'no_coverage',
                      'current_purpose_rule_coverage_missing')
    if check.get('state') != 'complete_assumption' or signal != 'none_assumption':
        return result(purpose, 'blocked_contract', 'blocked_contract', 'unreviewed', 'incomplete',
                      'actual_value_check_incomplete')
    normalized = versions.get('normalized')
    if not check.get('target_is_actual_new_value') or not normalized or \
            not all(ref == normalized for ref in [versions.get('checked'), versions.get('final'), check.get('target_ref')]):
        return result(purpose, 'ineligible', 'rejected', 'unreviewed', 'invalidated', 'actual_new_value_version_mismatch')
    if sensitivity == 'unreviewed' and purpose != 'local_supplier_name_write':
        return result(purpose, 'blocked_contract', 'blocked_contract', sensitivity, 'no_coverage',
                      'unreviewed_outbound_prohibited')
    if sensitivity == 'unreviewed':
        # Local is not globally gated by outbound coverage, but its own declaration is required.
        return result(purpose, 'blocked_contract', 'blocked_contract', sensitivity, 'no_coverage',
                      'local_purpose_context_missing')

    # Content eligible is separate from authority and mode. These facts are still only assumptions.
    gates = stimulus.get('execution_prerequisites', {})
    for name in ['scope', 'read_right', 'identity', 'capability', 'plan_revision', 'ledger']:
        if gates.get(name) != 'valid_assumption':
            return result(purpose, 'eligible', 'rejected', sensitivity, reason='hard_constraint_' + name)
    if gates.get('capability_hold', 'absent_assumption') != 'absent_assumption':
        return result(purpose, 'eligible', 'rejected', sensitivity, reason='capability_hold')
    if purpose == 'local_supplier_name_write':
        for name in ['write_right', 'cas', 'business_validity']:
            if gates.get(name) != 'valid_assumption':
                return result(purpose, 'eligible', 'rejected', sensitivity, reason='hard_constraint_' + name)
    elif gates.get('tls', 'valid_assumption_if_transport') != 'valid_assumption_if_transport':
        return result(purpose, 'eligible', 'rejected', sensitivity, reason='hard_constraint_tls')
    policy = stimulus.get('mode_facts', {})
    if policy.get('mode_grant') != 'valid_finite_synthetic_assumption':
        return result(purpose, 'eligible', 'blocked_contract', sensitivity, reason='mode_capability_missing')
    try:
        created, now, expires = [datetime.fromisoformat(policy[key].replace('Z', '+00:00'))
                                 for key in ['grant_created_at', 'evaluated_at', 'expires_at']]
        valid = created <= now < expires
    except (KeyError, TypeError, ValueError):
        valid = False
    if not valid:
        return result(purpose, 'eligible', 'rejected', sensitivity, reason='mode_capability_time_invalid')
    mode = policy.get('mode')
    if mode == 'FullAllow':
        return result(purpose, 'eligible', 'eligible', sensitivity, reason='FullAllow_current_scope_assumption')
    if mode == 'readOnly':
        if purpose == 'model_request':
            return result(purpose, 'eligible', 'blocked_contract', sensitivity,
                          reason='independent_model_authorization_not_supplied')
        return result(purpose, 'eligible', 'rejected', sensitivity, reason='readOnly_write_or_outbound_not_granted')
    if mode == 'everyAsk':
        return result(purpose, 'eligible', 'await_confirmation', sensitivity, reason='current_intent_confirmation_required')
    if mode != 'Auto':
        return result(purpose, 'eligible', 'blocked_contract', sensitivity, reason='legacy_mode_mapping_unfrozen')
    if policy.get('auto_risk_rule') != 'synthetic_frozen_assumption_for_routing_only':
        return result(purpose, 'eligible', 'blocked_contract', sensitivity, reason='Auto_risk_rule_unfrozen')
    risk = policy.get('risk')
    if risk == 'low':
        return result(purpose, 'eligible', 'eligible', sensitivity, reason='Auto_low_assumed_rule')
    if risk == 'high':
        return result(purpose, 'eligible', 'await_confirmation', sensitivity, reason='Auto_high_assumed_rule')
    if risk == 'prohibited_risk':
        return result(purpose, 'eligible', 'rejected', sensitivity, reason='Auto_prohibited_assumed_rule')
    return result(purpose, 'eligible', 'blocked_contract', sensitivity, reason='Auto_risk_domain_unfrozen')
