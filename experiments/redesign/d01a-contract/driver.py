"""Experimental comparison driver; oracle access is strictly after the DUT call.

Only this comparison layer reads fixture identity/expected. The DUT receives an
allowlisted deepcopy of stimulus sections. Original inputs are not rewritten.
"""
import argparse
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sys

from fixture_adapter import to_stimulus
from seam import decide

ROOT = Path(__file__).resolve().parents[3]
V1 = ROOT / 'fixtures/redesign/classification-v1'
V2 = ROOT / 'fixtures/redesign/classification-purpose-v2'
BODY_KEY = {'local_supplier_name_write': 'local_body_allowed',
            'model_request': 'model_body_allowed', 'business_outbound': 'business_outbound_allowed'}


def purpose_oracle(variant):
    purpose = variant['purpose']['current']
    return {'purpose': purpose, 'eligible': variant['expected'][BODY_KEY[purpose]],
            'noncurrent': 'not_applicable'}


def compare_variant(variant, dut=decide):
    stimulus = to_stimulus(variant)
    actual = dut(stimulus)  # No expected/identity has been accessed by this function yet.
    if actual['status'] == 'not_run':
        return {'actual': actual, 'oracle': None, 'mismatches': []}
    oracle = purpose_oracle(variant)
    expected_action = variant['expected']['action_result']
    mismatches = []
    if (actual['material']['state'] == 'eligible') != oracle['eligible']:
        mismatches.append('current_purpose_material')
    # Compare only independently specified route facets; do not claim full golden equivalence.
    expected_route = None
    if expected_action in {'eligible_under_fixture_assumptions_not_executed', 'auto_eligible_under_synthetic_frozen_rule'}:
        expected_route = 'eligible'
    elif expected_action == 'await_current_intent_confirmation':
        expected_route = 'await_confirmation'
    elif expected_action == 'blocked_contract_Auto_risk_rule':
        expected_route = 'blocked_contract'
    elif expected_action == 'risk_policy_reject_in_Auto' or expected_action.startswith('typed_'):
        expected_route = 'rejected'
    if expected_route is not None and actual['route']['state'] != expected_route:
        mismatches.append('mode_or_hard_constraint_route')
    if expected_action.startswith('blocked_') and actual['route']['state'] == 'eligible':
        mismatches.append('blocked_action_routed_eligible')
    return {'actual': actual, 'oracle': oracle, 'mismatches': mismatches}


def evaluate_matrix(poison_expected=False):
    manifest = json.loads((V1 / 'manifest.json').read_text())
    cases, sources = [], []
    poisoned = False
    for filename in manifest['case_files']:
        path = V1 / filename
        original = path.read_bytes()
        sources.append({'path': str(path.relative_to(ROOT)), 'sha256': hashlib.sha256(original).hexdigest()})
        case = json.loads(original)
        variants = []
        for variant in case['variants']:
            item = deepcopy(variant)
            # Deliberate oracle corruption only. No stimulus changes are made.
            if poison_expected and not poisoned and item['purpose']['current'] in BODY_KEY:
                key = BODY_KEY[item['purpose']['current']]
                item['expected'][key] = not item['expected'][key]
                poisoned = True
            compared = compare_variant(item)
            variants.append({'variant_id': variant['variant_id'], 'whole_variant_acceptance': 'not_run',
                             'experimental_status': compared['actual']['status'],
                             'comparison': 'not_run' if compared['actual']['status'] == 'not_run' else
                             'mismatch' if compared['mismatches'] else 'matched_partial_facets',
                             **compared})
        cases.append({'case_id': case['case_id'], 'original_case_status': case['execution_status'],
                      'whole_case_acceptance': 'not_run', 'variants': variants})
    all_variants = [v for c in cases for v in c['variants']]
    return {'artifact_kind': 'experimental_seam_observations_not_product_acceptance',
            'input_base': '1dc7678684c573f7f7e26ff8c6aa2a31f4d7c22d',
            'status': 'experimental', 'case_count': len(cases), 'variant_count': len(all_variants),
            'rules': '14 proposed_unfrozen', 'main_acceptance': '52 not_run',
            'whole_case_pass_count': 0, 'real_credential_scans': 0, 'real_model_requests': 0,
            'real_dispatches': 0, 'M03_frozen': False,
            'counts': {'partial_experimental': sum(v['experimental_status'] == 'partial_experimental' for v in all_variants),
                       'not_run': sum(v['experimental_status'] == 'not_run' for v in all_variants),
                       'partial_comparison_mismatches': sum(bool(v['mismatches']) for v in all_variants)},
            'expected_only_negative_control': poison_expected,
            'source_hashes': sources, 'cases': cases}


def derive_purpose_v2():
    """Representation-only I03 projection, separate from execution and original history."""
    V2.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((V1 / 'manifest.json').read_text())
    rows = []
    for filename in manifest['case_files']:
        case = json.loads((V1 / filename).read_text())
        for variant in case['variants']:
            projected = purpose_oracle(variant)
            rows.append({'case_id': case['case_id'], 'variant_id': variant['variant_id'],
                         'original_fixture_status': 'not_run', 'whole_variant_acceptance': 'not_run',
                         'stimulus': to_stimulus(variant),
                         'oracle': {'current_purpose_material_eligibility': projected,
                                    'action_result': variant['expected']['action_result'],
                                    'eligibility_does_not_authorize_dispatch': True}})
    path = V2 / 'purpose-records.json'
    path.write_text(json.dumps({'artifact_kind': 'fixture_only_purpose_projection_not_product_schema',
                              'status': 'draft', 'execution_status': 'not_run', 'records': rows},
                             ensure_ascii=False, indent=2) + '\n')
    (V2 / 'manifest.json').write_text(json.dumps({
        'artifact_kind': 'derived_fixture_index', 'case_count': 29, 'variant_count': 77,
        'status': 'draft', 'execution_status': 'not_run', 'main_acceptance': '52 not_run',
        'rules': '14 proposed_unfrozen', 'source_manifest': str((V1 / 'manifest.json').relative_to(ROOT)),
        'source_manifest_sha256': hashlib.sha256((V1 / 'manifest.json').read_bytes()).hexdigest(),
        'records_file': path.name,
        'derivation': 'only current-purpose oracle field retained; all noncurrent not_applicable; no dispatch grant',
        'source_hashes': [{'path': filename, 'sha256': hashlib.sha256((V1 / filename).read_bytes()).hexdigest()}
                          for filename in manifest['case_files']]}, ensure_ascii=False, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--mutate-expected', action='store_true')
    parser.add_argument('--derive-purpose-v2', action='store_true')
    args = parser.parse_args()
    if args.derive_purpose_v2:
        derive_purpose_v2()
    report = evaluate_matrix(args.mutate_expected)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'counts': report['counts'], 'case_count': report['case_count'],
                      'variant_count': report['variant_count'], 'whole_case_pass_count': 0}, sort_keys=True))
    return 1 if report['counts']['partial_comparison_mismatches'] else 0


if __name__ == '__main__': sys.exit(main())
