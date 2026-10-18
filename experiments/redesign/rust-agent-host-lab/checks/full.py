"""Strict GREEN evidence, kept separate from reachable RED classification."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re

CASES = json.loads(Path(__file__).with_name('cases.json').read_text())


def rust(component, text, status, *, contract=None):
    if contract == 'combined':
        from http_batch import contract as combined_contract
        contract = combined_contract()
    expected = (CASES if contract is None else contract)['components'][component]
    groups = []
    current = None
    for line in text.splitlines():
        unit = re.match(r'^\s*Running unittests (\S+) \(', line)
        integration = re.match(r'^\s*Running tests/(\w+)\.rs \(', line)
        doc = re.match(r'^\s*Doc-tests (\S+)', line)
        if unit or integration or doc:
            key = 'unit:' + unit[1] if unit else 'integration:' + integration[1] if integration else 'doc:' + doc[1]
            current = dict(key=key, names=[], statuses=[], summaries=[])
            groups.append(current)
        if current is not None:
            case = re.match(r'^test (\S+) \.\.\. (ok|FAILED|ignored)\s*$', line)
            summary = re.match(r'^test result: (ok|FAILED)\. (\d+) passed; (\d+) failed; (\d+) ignored; (\d+) measured; (\d+) filtered out;', line)
            if case:
                current['names'].append(case[1]); current['statuses'].append(case[2])
            if summary:
                current['summaries'].append(list(summary.groups()))
    valid = status == 0 and bool(re.search(r'Finished [^\n]*test[^\n]*profile', text))
    seen = Counter(group['key'] for group in groups)
    valid = valid and all(count == 1 for count in seen.values()) and set(expected['groups']).issubset(seen)
    families = Counter()
    for group in groups:
        contract = expected['groups'].get(group['key'])
        names = contract['names'] if contract else []
        allowed_empty = group['key'].startswith(('unit:', 'doc:'))
        valid = (valid and (contract is not None or allowed_empty)
                 and Counter(group['names']) == Counter(names)
                 and all(value == 'ok' for value in group['statuses'])
                 and group['summaries'] == [['ok', str(len(names)), '0', '0', '0', '0']])
        if contract:
            families[contract['family']] += len(group['names'])
    total = sum(len(group['names']) for group in groups)
    valid = valid and total == expected['expected_total']
    return dict(accepted=bool(valid), classification='full_green' if valid else 'INVALID',
                component=component, expected_tests=expected['expected_total'], observed_tests=total,
                families=dict(families), unit_tests=sum(len(g['names']) for g in groups if g['key'].startswith('unit:')),
                doc_tests=sum(len(g['names']) for g in groups if g['key'].startswith('doc:')),
                groups=groups, command_exit_code=status)


def python_suite(name, text, status):
    expected = CASES['python'][name]
    observed = re.findall(r'^(test_\w+) \(', text, re.M)
    totals = re.findall(r'^Ran (\d+) tests? in ', text, re.M)
    valid = (status == 0 and Counter(observed) == Counter(expected)
             and totals == [str(len(expected))] and len(re.findall(r'^OK\s*$', text, re.M)) == 1
             and not re.search(r'^FAILED\b|\bskipped=', text, re.M))
    return dict(accepted=bool(valid), classification='full_green' if valid else 'INVALID',
                suite=name, expected_methods=len(expected), observed_methods=len(observed),
                command_exit_code=status)


def mutations(rows, status):
    names = [row.get('name') for row in rows]
    valid = (status == 0 and Counter(names) == Counter(CASES['mutants'])
             and all(row.get('compiled') is True and row.get('killed') is True
                     and row.get('returncode') == (1 if row.get('name') == 'wire_preterminal_physical_effect' else 101) for row in rows))
    for row in rows:
        if row.get('name') == 'wire_preterminal_physical_effect':
            valid = valid and row.get('acknowledged') is True and row.get('physical_failure') is True
        else:
            valid = valid and bool(re.fullmatch(r'test \S+ \.\.\. FAILED', row.get('first_failure', '')))
    return dict(accepted=bool(valid), classification='legacy_mutants_killed' if valid else 'INVALID',
                expected_mutants=17, observed_mutants=len(rows), command_exit_code=status)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('kind', choices=['rust', 'python', 'mutants'])
    parser.add_argument('--name', required=True)
    parser.add_argument('--contract', choices=['product', 'combined'], default='product')
    parser.add_argument('--log', type=Path, required=True)
    parser.add_argument('--status', type=int, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    raw = args.log.read_bytes() if args.log.is_file() else b''
    try:
        text = raw.decode('utf-8')
        result = (rust(args.name, text, args.status, contract='combined' if args.contract == 'combined' else None) if args.kind == 'rust' else
                  python_suite(args.name, text, args.status) if args.kind == 'python' else
                  mutations(json.loads(text), args.status))
    except (ValueError, KeyError, TypeError, AttributeError):
        result = dict(accepted=False, classification='INVALID', command_exit_code=args.status)
    result['contract'] = args.contract
    result['raw_sha256'] = hashlib.sha256(raw).hexdigest()
    result['expectations_sha256'] = hashlib.sha256(Path(__file__).with_name('cases.json').read_bytes()).hexdigest()
    if args.contract == 'combined':
        from http_batch import contract as combined_contract
        result['expectations_sha256'] = hashlib.sha256(json.dumps(combined_contract(), sort_keys=True).encode()).hexdigest()
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))
    return 0 if result['accepted'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
