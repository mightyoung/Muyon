#!/usr/bin/env python3
"""Pin fixtures/source, invoke actual Dart, compare independent semantic vectors.

Python never normalizes or validates supplier names. Recipe decoding here is only
for literal expected outputs; every input recipe is decoded by Dart.
"""
import argparse
import collections
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

PRODUCT = '01e56cc2d729dab70e1b1def05c3aa93b28f421a'
DESIGN = '58fe9c62612d74a973614c41677e62a54332e6d6'
FIXTURES = 'fixtures/redesign/supplier-name-v1'
FILENAMES = ['name-domain-vectors.json', 'entry-comparisons.json',
             'planned-state-semantics.json']
ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
SOURCES = ['packages/supplier_core/lib/src/' + n + '.dart'
           for n in ['values', 'entities', 'inquiry']]


def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args])


def digest(data):
    return hashlib.sha256(data).hexdigest()


def expected_value(recipe):
    if 'literal' in recipe:
        return recipe['literal']
    if 'repeat' in recipe:
        r = recipe['repeat']
        return r['literal'] * r['count']
    if 'concat' in recipe:
        return ''.join(map(expected_value, recipe['concat']))
    raise ValueError('unsupported expected output recipe')


def comparison(actual, expected):
    if expected['outcome'] == 'FormatException':
        return (actual['outcome'] == 'rejected' and
                actual['reason'] == expected['field'] + ': ' + expected['reason'])
    if expected['outcome'] == 'value':
        return (actual['outcome'] == 'accepted' and
                actual.get('normalized') == expected_value(expected['value_recipe']))
    raise ValueError('unsupported expectation')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fixture-sha', required=True)
    parser.add_argument('--dart', default='/workspace/flutter-sdk/bin/cache/dart-sdk/bin/dart')
    parser.add_argument('--unorm', default='/workspace/pub-cache/hosted/pub.dev/unorm_dart-0.3.1')
    parser.add_argument('--evidence-dir', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    if not re.fullmatch('[0-9a-f]{40}', args.fixture_sha):
        raise ValueError('full fixture SHA required')
    evidence = Path(args.evidence_dir).resolve()
    if evidence.is_relative_to(ROOT):
        raise ValueError('raw evidence must be outside repository')
    output = Path(args.output).resolve()
    if not output.is_relative_to(HERE):
        raise ValueError('machine results must stay in M05 reserved script directory')
    evidence.mkdir(parents=True, exist_ok=True)
    source_hashes = {}
    for name in SOURCES:
        fixed = git('show', PRODUCT + ':' + name)
        if (ROOT / name).read_bytes() != fixed:
            raise ValueError('source differs from product pin: ' + name)
        source_hashes[name] = digest(fixed)
    fixtures = []
    fixture_hashes = {}
    for name in FILENAMES:
        raw = git('show', args.fixture_sha + ':' + FIXTURES + '/' + name)
        fixture_hashes[name] = digest(raw)
        data = json.loads(raw)
        if data['product_source_sha'] != PRODUCT or data['design_source_sha'] != DESIGN:
            raise ValueError('fixture source pin mismatch')
        fixtures.append(data)
    unorm = Path(args.unorm).resolve()
    pubspec = (unorm / 'pubspec.yaml').read_text()
    if 'version: 0.3.1\n' not in pubspec:
        raise ValueError('unexpected normalization package version')
    dependency_hashes = {str(p.relative_to(unorm)): digest(p.read_bytes())
                         for p in sorted((unorm / 'lib').rglob('*.dart'))}
    config = evidence / 'package_config.json'
    config.write_text(json.dumps({'configVersion': 2, 'packages': [{
        'name': 'unorm_dart', 'rootUri': unorm.as_uri() + '/',
        'packageUri': 'lib/', 'languageVersion': '2.12'}]}, indent=2))
    invocations = []
    expectations = {}
    rows = []
    for data in fixtures:
        for case in data['cases']:
            cid = case['case_id']
            row = {'case_id': cid, 'fixture_status': case['status'],
                   'rust_target_status': 'not_run', 'entries': []}
            rows.append(row)
            if data['kind'] == 'actual_dart_normalizer_inputs':
                invocations.append({'invocation_id': cid, 'entry_point': 'normalizeText',
                                    'input': case['input_recipe'], 'safe_output': True})
                expectations[cid] = case['proposed_semantics']
                row['entries'].append({'entry': 'normalizeText', 'invocation_id': cid})
                row['coverage'] = 'exact_declared_normalizer_entry_only'
                if cid == 'M04-NAME-chinese':
                    iid = cid + '/complete-supplier-constructor'
                    invocations.append({'invocation_id': iid, 'entry_point': 'Supplier.fromJson',
                                        'input': case['input_recipe'], 'safe_output': True,
                                        'complete_supplier_from_name': True})
                    expectations[iid] = case['proposed_semantics']
                    row['entries'].append({'entry': 'Supplier.fromJson supplementary positive',
                                           'invocation_id': iid})
            elif 'proposed_semantics_by_entry' in case:
                entries = case['proposed_semantics_by_entry']
                supplier = entries.get('Supplier.fromJson')
                if supplier:
                    invocations.append({'invocation_id': cid, 'entry_point': 'Supplier.fromJson',
                                        'input': case['input_recipe'], 'safe_output': False})
                    expectations[cid] = supplier
                    row['entries'].append({'entry': 'Supplier.fromJson', 'invocation_id': cid})
                    row['entries'].append({'entry': 'validatePayload dispatch', 'status': 'not_run',
                                           'reason': 'only actual supplier branch constructor invoked'})
                # Original UI/preflight/target entries remain not_run, even when
                # a narrower raw normalizer observation is available.
                for entry, exp in entries.items():
                    if entry == 'Supplier.fromJson':
                        continue
                    row['entries'].append({'entry': entry, 'status': 'not_run',
                                           'reason': 'actual controller/private host guard/schema/target not invoked'})
                if not supplier and any('normalize' in key for key in entries):
                    iid = cid + '/raw-normalizer-only'
                    invocations.append({'invocation_id': iid, 'entry_point': 'normalizeText',
                                        'input': case['input_recipe'], 'safe_output': True})
                    row['entries'].append({'entry': 'normalizeText supplementary observation',
                                           'invocation_id': iid})
                row['coverage'] = 'partial_or_source_only_entry_comparison'
            else:
                row['coverage'] = 'planned_state_contract_not_executed'
                row['entries'].append({'entry': 'planned state runner', 'status': 'not_run',
                                       'reason': 'no actual trusted scope CAS intent receipt path invoked'})
    ids = [i['invocation_id'] for i in invocations]
    if len(ids) != len(set(ids)) or not expectations:
        raise ValueError('empty or duplicate invocation set')
    invocation_file = evidence / 'invocations.json'
    invocation_file.write_text(json.dumps(invocations, ensure_ascii=True, indent=2))
    env = os.environ.copy()
    env.update(CI='true', XDG_CONFIG_HOME='/workspace/sdk-config', PUB_CACHE='/workspace/pub-cache')
    env.pop('MUYON_EVAL_REAL', None)
    command = [args.dart, '--packages=' + str(config), str(HERE / 'oracle.dart'), str(invocation_file)]
    completed = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True)
    (evidence / 'dart.stdout.json').write_text(completed.stdout)
    (evidence / 'dart.stderr.log').write_text(completed.stderr)
    if completed.returncode:
        print('Dart failed; diagnostic evidence outside repository:', evidence, file=sys.stderr)
        return completed.returncode
    results = json.loads(completed.stdout)
    if len(results) != len(ids) or {r['invocation_id'] for r in results} != set(ids):
        raise ValueError('missing or surplus actual results')
    results_by_id = {r['invocation_id']: r for r in results}
    checked = []
    for row in rows:
        executed = False
        failed = False
        for entry in row['entries']:
            iid = entry.pop('invocation_id', None)
            if iid:
                executed = True
                result = results_by_id[iid]
                entry['actual'] = result
                if iid in expectations:
                    ok = comparison(result, expectations[iid])
                    checked.append((iid, result['outcome'], ok))
                    entry['status'] = 'pass' if ok else 'fail'
                    failed |= not ok
                else:
                    entry['status'] = 'observed_only'
        row['actual_status'] = ('fail' if failed else 'pass') if row['coverage'].startswith('exact_') else (
            'partial' if executed and not failed else 'fail' if failed else 'not_run')
    # Non-vacuity: independent fixed M04 vectors must actually exercise both
    # accepted and rejected branches, NFC composition and XML-before-trim.
    by_id = {r['invocation_id']: r for r in results}
    required = {'M04-NAME-nfc-compose': 'accepted', 'M04-NAME-cjk-201': 'rejected',
                'M04-NAME-vt-edge': 'rejected', 'M04-NAME-valid-surrogate-pair': 'accepted',
                'M04-NAME-isolated-high-surrogate': 'rejected'}
    for cid, outcome in required.items():
        if by_id.get(cid, {}).get('outcome') != outcome:
            raise ValueError('anti-vacuity branch missing: ' + cid)
    if not all(any(outcome == wanted and ok for _, outcome, ok in checked)
               for wanted in ['accepted', 'rejected']):
        raise ValueError('anti-vacuity missing positive or negative comparison')
    report = {'format': 'm05-dart-reference-observations-v1', 'product_source_sha': PRODUCT,
              'design_source_sha': DESIGN, 'fixture_commit_sha': args.fixture_sha,
              'oracle_worktree_base_sha': git('rev-parse', 'HEAD').decode().strip(),
              'oracle_file_sha256': digest((HERE / 'oracle.dart').read_bytes()),
              'driver_file_sha256': digest(Path(__file__).read_bytes()),
              'dart_version': subprocess.check_output([args.dart, '--version'], env=env, text=True).strip(),
              'normalization_dependency': {'package': 'unorm_dart', 'version': '0.3.1',
                'declared_unicode_data': '8.0 (package pubspec description)', 'lib_sha256': dependency_hashes},
              'source_sha256': source_hashes, 'fixture_sha256': fixture_hashes,
              'command': command, 'dart_exit_code': completed.returncode,
              'anti_vacuity': 'pass', 'cross_end_unicode_equivalence': 'not_proven',
              'M03': 'blocked_contract', 'cases': rows,
              'summary': dict(collections.Counter(r['actual_status'] for r in rows)),
              'checked_invocations': len(checked), 'actual_invocations': len(results),
              'mismatches': sum(not ok for _, _, ok in checked)}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=True, indent=2) + '\n')
    print(json.dumps({k: report[k] for k in ['summary', 'checked_invocations', 'actual_invocations', 'mismatches']}))
    return 1 if report['mismatches'] else 0


if __name__ == '__main__':
    sys.exit(main())
