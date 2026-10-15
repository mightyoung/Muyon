#!/usr/bin/env python3
"""Compile precise Dart DUT inverses in private source copies; never edit source.

Only exact target matcher failures count. Each unchanged oracle must first pass
on the real compiled Rust baseline. Raw logs/JSON and hashes stay outside Git.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from urllib.parse import unquote, urlsplit


ORACLE = 'test_host/core_agent_host_inverse_oracles_test.dart'
MUTATIONS = [
    {
        'name': 'host_projection_extra_reference_field',
        'file': 'apps/muyon/lib/assistant/core_agent_protocol.dart',
        'before': "        'contentDigest': optional(ref.contentDigest),",
        'after': "        'contentDigest': optional(ref.contentDigest),\n        'nativeProjectId': ref.nativeProjectId,",
        'target': 'actual host projection contains only accepted reference fields',
        'marker': 'HOST_PROJECTION_FIELDS',
    },
    {
        'name': 'host_native_call_correlation_removed',
        'file': 'apps/muyon/lib/assistant/core_agent_process.dart',
        'before': "        frame['call_id'] != proposed!['call_id'] ||\n",
        'after': '',
        'target': 'wrong native call identity cannot create a registry receipt',
        'marker': 'HOST_AUTHORITY_BINDING',
    },
    {
        'name': 'host_second_driver_admission',
        'file': 'apps/muyon/lib/assistant/core_agent_process.dart',
        'before': '    if (_active != null) {',
        'after': '    if (false && _active != null) {',
        'target': 'concurrent actual core starts retain exactly one process launch',
        'marker': 'HOST_ONE_DRIVER_LAUNCH_COUNT',
    },
]


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def events(path):
    if not path.exists():
        return []
    try:
        return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
    except (ValueError, OSError):
        return []


def classify(rows, returncode, target, marker=None):
    starts = [row['test'] for row in rows if row.get('type') == 'testStart'
              and row.get('test', {}).get('name') == target]
    if len(starts) != 1:
        return {'compiled': False, 'accepted': False, 'reason': 'target_not_started'}
    test_id = starts[0]['id']
    completed = [row for row in rows if row.get('type') == 'testDone' and row.get('testID') == test_id]
    terminal = [row for row in rows if row.get('type') == 'done']
    errors = [row for row in rows if row.get('type') == 'error']
    failed = [row for row in rows if row.get('type') == 'testDone' and row.get('result') != 'success']
    valid_done = len(completed) == 1 and not completed[0].get('skipped', False) and len(terminal) == 1
    if marker is None:
        accepted = (valid_done and returncode == 0 and completed[0]['result'] == 'success'
                    and terminal[0].get('success') is True and not errors and not failed)
    else:
        # A true matcher failure after the named test starts proves the Dart
        # frontend compiled the DUT and the unchanged oracle actually executed.
        accepted = (valid_done and returncode == 1 and completed[0]['result'] == 'failure'
                    and terminal[0].get('success') is False and len(errors) == 1
                    and errors[0].get('testID') == test_id and errors[0].get('isFailure') is True
                    and marker in errors[0].get('error', '') and len(failed) == 1
                    and failed[0].get('testID') == test_id)
    return {'compiled': True, 'accepted': accepted,
            'reason': 'expected_target_assertion' if accepted and marker else
                      'baseline_pass' if accepted else 'unrelated_failure_or_survived'}


def copy_sources(source, destination):
    tracked = subprocess.check_output(['git', '-C', str(source), 'ls-files', '-z']).split(b'\0')
    for encoded in tracked:
        if not encoded:
            continue
        relative = Path(os.fsdecode(encoded))
        origin = source / relative
        if not origin.is_file() and not origin.is_symlink():
            continue
        copied = destination / relative
        copied.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(origin, copied, follow_symlinks=False)
    config_path = source / '.dart_tool/package_config.json'
    config = json.loads(config_path.read_text())
    for package in config['packages']:
        uri = package['rootUri']
        parsed = urlsplit(uri)
        if parsed.scheme == 'file':
            resolved = Path(unquote(parsed.path)).resolve()
        elif not parsed.scheme:
            resolved = (config_path.parent / unquote(uri)).resolve()
        else:
            raise RuntimeError('unsupported_package_root_scheme')
        if resolved.is_relative_to(source):
            package['rootUri'] = (destination / resolved.relative_to(source)).as_uri()
        else:
            package['rootUri'] = resolved.as_uri()
    mapped = {package['name']: package['rootUri'] for package in config['packages']}
    if mapped.get('muyon') != (destination / 'apps/muyon').as_uri():
        raise RuntimeError('private_copy_dut_package_not_selected')
    config_copy = destination / '.dart_tool/package_config.json'
    config_copy.parent.mkdir(parents=True, exist_ok=True)
    config_copy.write_text(json.dumps(config, indent=2) + '\n')


def run_oracle(work, binary, flutter, evidence, label, mutation=None):
    target = mutation['target'] if mutation else label
    machine = evidence / (label + '.jsonl')
    log = evidence / (label + '.log')
    command = [flutter, 'test', ORACLE, '--no-pub', '--reporter', 'expanded',
               '--file-reporter', 'json:' + str(machine), '--timeout', '45s',
               '--plain-name', target]
    environment = dict(os.environ, MUYON_TEST_CORE_AGENT_BIN=str(binary),
                       MUYON_TEST_CORE_AGENT_EVIDENCE_DIR=str(evidence / (label + '-processes')))
    for key in ['HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'http_proxy', 'https_proxy', 'all_proxy']:
        environment.pop(key, None)
    environment['NO_PROXY'] = 'localhost,127.0.0.1,::1'
    record = {'name': label, 'target': target, 'command': command, 'copy': str(work),
              'binary_sha256': digest(binary), 'log': str(log), 'json': str(machine)}
    try:
        run = subprocess.run(command, cwd=work / 'apps/muyon', env=environment,
                             text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=240)
    except subprocess.TimeoutExpired as error:
        output = error.stdout or b''
        log.write_bytes(output.encode() if isinstance(output, str) else output)
        return dict(record, compiled=False, accepted=False, reason='runner_timeout')
    log.write_text(run.stdout)
    verdict = classify(events(machine), run.returncode, target, mutation['marker'] if mutation else None)
    return dict(record, returncode=run.returncode, **verdict)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--evidence-dir', type=Path, required=True)
    parser.add_argument('--binary', type=Path, required=True)
    parser.add_argument('--flutter', default=shutil.which('flutter'))
    arguments = parser.parse_args()
    source = Path(__file__).resolve().parents[4]
    evidence = arguments.evidence_dir.resolve()
    binary = arguments.binary.resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    if not binary.is_file() or not os.access(binary, os.X_OK) or not arguments.flutter:
        raise SystemExit('required_real_binary_or_flutter_missing')
    original = {mutation['file']: digest(source / mutation['file']) for mutation in MUTATIONS}
    original_binary = digest(binary)
    manifest = {'source_sha': subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip(),
                'binary_sha256': original_binary, 'dut_sources': original,
                'oracle_sha256': digest(source / 'apps/muyon' / ORACLE)}
    (evidence / 'source-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    results = []
    try:
        with tempfile.TemporaryDirectory(prefix='core-host-dut-inverses-') as temporary:
            directory = Path(temporary)
            baseline = directory / 'baseline'
            copy_sources(source, baseline)
            # Each exact unchanged target must independently pass before its
            # mutant can be evaluated. No baseline failure is a mutation kill.
            for mutation in MUTATIONS:
                baseline_result = run_oracle(baseline, binary, arguments.flutter, evidence,
                    'baseline-' + mutation['name'], {'target': mutation['target'], 'marker': None})
                results.append(baseline_result)
                if not baseline_result['accepted']:
                    raise RuntimeError('baseline_not_green:' + mutation['name'])
                work = directory / mutation['name']
                copy_sources(source, work)
                path = work / mutation['file']
                text = path.read_text()
                if text.count(mutation['before']) != 1:
                    raise RuntimeError('mutation_anchor_not_unique:' + mutation['name'])
                path.write_text(text.replace(mutation['before'], mutation['after'], 1))
                (evidence / (mutation['name'] + '.patch.json')).write_text(json.dumps(mutation, indent=2) + '\n')
                mutated_source = evidence / (mutation['name'] + '.mutated-source.dart')
                shutil.copy2(path, mutated_source)
                result = run_oracle(work, binary, arguments.flutter, evidence, mutation['name'], mutation)
                result['mutated_source_sha256'] = digest(path)
                result['mutated_source'] = str(mutated_source)
                results.append(result)
                print(mutation['name'] + ': ' + ('KILLED' if result['accepted'] else 'INVALID_OR_SURVIVED'), flush=True)
                if not result['accepted']:
                    raise RuntimeError('mutant_not_target_assertion:' + mutation['name'])
    finally:
        unchanged = all(digest(source / file) == value for file, value in original.items()) and digest(binary) == original_binary
        summary = {'baselines_passed': sum(row['accepted'] for row in results if row['name'].startswith('baseline-')),
                   'killed': sum(row['accepted'] for row in results if not row['name'].startswith('baseline-')),
                   'required': len(MUTATIONS), 'original_sources_unchanged': unchanged, 'results': results}
        (evidence / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
        if not unchanged:
            raise RuntimeError('original_sources_changed')
    print('HOST DUT INVERSES: 3 baselines PASS; 3/3 compiled target assertions KILLED')


if __name__ == '__main__':
    main()
