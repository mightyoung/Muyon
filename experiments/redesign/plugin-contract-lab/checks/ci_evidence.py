"""Independent CI evidence contract frozen before DUT implementation."""
import argparse
import hashlib
import json
from pathlib import Path
import re

SPEC_SHA = 'e0b3df04514e53eb7fad7e21578c34bce2a5e6e4'
RUST_CASES = {
    'atomic_registration_publishes_only_valid_bundle',
    'registration_neither_grants_nor_reads',
    'namespace_duplicates_and_versions_reject',
    'schema_subset_and_limits_fail_closed',
    'relation_and_view_refs_must_resolve',
    'discovery_filters_current_authority',
    'declaration_labels_cannot_authorize',
    'renamed_bundle_is_semantically_equivalent',
    'prepared_bindings_are_exact',
    'revoke_before_invoke_executes_zero',
    'ticket_is_one_shot',
    'receipt_reference_has_original_owner',
    'invalid_projection_and_refs_reject',
    'cancel_before_dispatch_executes_zero',
    'cancel_after_dispatch_accepts_no_projection',
    'eof_and_concurrency_fail_closed',
}
DART_CASES = {
    'registrar preserves sensitivity without granting',
    'actual declarations map three distinct read contracts',
    'permission filtered catalog drives selection',
    'live revoke and scope changes prevent handler execution',
    'owner receipt survives projection rejection',
    'cancel and process failure preserve owner semantics',
    'registered read reaches original receipt and reviewed model projection',
    'renamed third module retains source and purpose gates',
    'raw summary result and toolLog cannot leak',
    'plugin labels cannot clear source facts or classify values',
    'final model payload review remains authoritative',
    'no port preserves legacy and missing projection fails closed',
}
RUST_RED = 'atomic_registration_publishes_only_valid_bundle'
DART_RED = 'registered read reaches original receipt and reviewed model projection'
RUST_MARKER = 'PLUGIN_SLICE_RED_RUST_ATOMIC_PUBLICATION'
DART_MARKER = 'PLUGIN_SLICE_RED_DART_AGENT_READ'
REGISTRATION_CASES = {
    'atomic_registration_publishes_only_valid_bundle', 'registration_neither_grants_nor_reads',
    'namespace_duplicates_and_versions_reject', 'schema_subset_and_limits_fail_closed',
    'relation_and_view_refs_must_resolve', 'discovery_filters_current_authority',
    'declaration_labels_cannot_authorize', 'renamed_bundle_is_semantically_equivalent',
}


def verdict(accepted, reason, **extra):
    return dict(accepted=accepted, reason=reason, spec_sha=SPEC_SHA, **extra)


def rust_result(text, exit_code, red=False):
    # Compilation failures also use101, so require actual named test execution.
    rows = re.findall(r'^test (\S+) \.\.\. (ok|FAILED|ignored)\s*$', text, re.M)
    summaries = re.findall(r'^test result: (ok|FAILED)\. (\d+) passed; (\d+) failed; (\d+) ignored; (\d+) measured; (\d+) filtered out;', text, re.M)
    groups = []
    current = None
    for line in text.splitlines():
        running = re.match(r'^\s*Running (.+?)\s+\(', line)
        docs = re.match(r'^\s*Doc-tests (\S+)', line)
        if running or docs:
            label = running.group(1) if running else docs.group(1)
            kind = 'doc' if docs else 'unit' if label.startswith('unittests ') else 'integration'
            current = dict(kind=kind, target=label, cases=[], summaries=[])
            groups.append(current)
        if current is not None:
            case = re.match(r'^test (\S+) \.\.\. (ok|FAILED|ignored)\s*$', line)
            summary = re.match(r'^test result: (ok|FAILED)\. (\d+) passed; (\d+) failed; (\d+) ignored; (\d+) measured; (\d+) filtered out;', line)
            if case:
                current['cases'].append(case.groups())
            if summary:
                current['summaries'].append(summary.groups())
    compiled = bool(re.search(r'Finished [^\n]*test[^\n]*profile', text))
    if not compiled or not rows or not summaries:
        return verdict(False, 'compile_or_target_not_started', compiled=compiled)
    if re.search(r'timed out|SIGABRT|SIGKILL', text, re.I):
        return verdict(False, 'timeout_or_process_failure', compiled=True)
    if red:
        panic = re.search(r"^thread '" + re.escape(RUST_RED)
                          + r"'(?: \(\d+\))? panicked at [^\n]+:\n([^\n]*)", text, re.M)
        accepted = (exit_code == 101 and rows == [(RUST_RED, 'FAILED')]
                    and len(summaries) == 1
                    and summaries[0] == ('FAILED', '0', '1', '0', '0', '7')
                    and len(groups) == 1 and groups[0]['target'] == 'tests/registration.rs'
                    and panic is not None and RUST_MARKER in panic.group(1))
        return verdict(accepted, 'semantic_red' if accepted else 'invalid_red',
                       compiled=True, test_count=len(rows), command_exit_code=exit_code)
    integrations = [group for group in groups if group['kind'] == 'integration']
    other = [group for group in groups if group['kind'] != 'integration']
    expected = {'tests/registration.rs': REGISTRATION_CASES,
                'tests/read_contract.rs': RUST_CASES - REGISTRATION_CASES}
    exact_groups = len(integrations) == 2 and {group['target'] for group in integrations} == set(expected)
    for group in integrations:
        exact_groups = (exact_groups and len(group['cases']) == 8
                        and {name for name, _ in group['cases']} == expected.get(group['target'])
                        and group['summaries'] == [('ok', '8', '0', '0', '0', '0')])
    accepted = (exit_code == 0 and exact_groups and len(rows) == 16
                and all(status == 'ok' for _, status in rows)
                and all(not group['cases'] and group['summaries'] == [('ok', '0', '0', '0', '0', '0')]
                        for group in other)
                and sum(len(group['summaries']) for group in groups) == len(summaries))
    return verdict(accepted, 'full_green' if accepted else 'invalid_full',
                   compiled=True, test_count=sum(len(group['cases']) for group in integrations),
                   unit_test_count=sum(len(group['cases']) for group in other if group['kind'] == 'unit'),
                   doc_test_count=sum(len(group['cases']) for group in other if group['kind'] == 'doc'),
                   command_exit_code=exit_code, harness_groups=groups)


def dart_result(rows, exit_code, red=False, existing_regressions=False):
    started = [row['test'] for row in rows if row.get('type') == 'testStart']
    tests = {test['id']: test for test in started}
    if len(tests) != len(started):
        return verdict(False, 'duplicate_test_identity', compiled=False)
    expected = ({test['name'] for test in started if not test['name'].startswith('loading ')
                 and not test['name'].endswith(('(setUpAll)', '(tearDownAll)'))}
                if existing_regressions else {DART_RED} if red else DART_CASES)
    if not expected:
        return verdict(False, 'no_tests_started', compiled=False)
    selected = {identifier: test for identifier, test in tests.items() if test['name'] in expected}
    if len(selected) != len(expected) or {test['name'] for test in selected.values()} != expected:
        return verdict(False, 'compile_or_target_not_started', compiled=bool(selected),
                       test_count=len(selected), expected_count=len(expected))
    errors = [row for row in rows if row.get('type') == 'error']
    done = [row for row in rows if row.get('type') == 'done']
    completed = [row for row in rows if row.get('type') == 'testDone']
    by_id = {identifier: [row for row in completed if row['testID'] == identifier] for identifier in selected}
    unknown = [test['name'] for test in tests.values() if test['name'] not in expected
               and not test['name'].startswith('loading ')
               and not test['name'].endswith(('(setUpAll)', '(tearDownAll)'))]
    no_skips = not any(row.get('skipped') for row in completed) and not any(
        test.get('metadata', {}).get('skip') for test in tests.values())
    terminal = len(done) == 1 and not unknown and no_skips and all(len(value) == 1 for value in by_id.values())
    if red:
        identifier = next(iter(selected))
        accepted = (terminal and exit_code == 1 and done[0].get('success') is False
                    and len(errors) == 1 and errors[0].get('testID') == identifier
                    and errors[0].get('isFailure') is True and DART_MARKER in errors[0].get('error', '')
                    and not re.search(r'TimeoutException|timed out', errors[0].get('error', ''), re.I)
                    and by_id[identifier][0].get('result') == 'failure'
                    and sum(row.get('result') == 'failure' for row in completed) == 1)
    else:
        accepted = (terminal and exit_code == 0 and done[0].get('success') is True and not errors
                    and all(row.get('result') == 'success' for row in completed))
    return verdict(accepted, ('semantic_red' if red else 'existing_regressions_green' if existing_regressions
                              else 'full_green') if accepted else 'invalid_evidence',
                   compiled=True, test_count=len(selected), command_exit_code=exit_code,
                   count_contract='existing_file_scope' if existing_regressions else 'frozen_plan')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--language', choices=['rust', 'dart'], required=True)
    parser.add_argument('--mode', choices=['red', 'full', 'regressions'], required=True)
    parser.add_argument('--log', type=Path, required=True)
    parser.add_argument('--exit-code', type=int, required=True)
    parser.add_argument('--output', type=Path, required=True)
    arguments = parser.parse_args()
    raw = b''
    try:
        raw = arguments.log.read_bytes()
        if arguments.language == 'rust':
            result = rust_result(raw.decode(), arguments.exit_code, arguments.mode == 'red')
        else:
            rows = [json.loads(line) for line in raw.decode().splitlines() if line.strip()]
            result = dart_result(rows, arguments.exit_code, arguments.mode == 'red',
                                 arguments.mode == 'regressions')
    except (OSError, ValueError, KeyError, TypeError, UnicodeError, AttributeError, IndexError):
        result = verdict(False, 'malformed_evidence', compiled=False)
    result.update(language=arguments.language, mode=arguments.mode,
                  command_exit_code=arguments.exit_code, red_requires_ci_failure=arguments.mode == 'red',
                  evidence_sha256=hashlib.sha256(raw).hexdigest())
    arguments.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))
    return 0 if result['accepted'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
