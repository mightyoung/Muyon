#!/usr/bin/env python3
"""Collect explicitly supplied Linux evidence; never execute validation commands."""

import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import stat

STAGES = ('unit_widget', 'linux_build', 'linux_launch', 'linux_interaction')
LABELS = ('单元/组件', 'Linux 构建', 'Linux 启动', 'Linux 交互')
MAX_BYTES = 10 * 1024 * 1024


def forbidden(path):
    """Reject credential paths before opening, including parent directories."""
    return any(part.lower().startswith('.env') or part.lower() in {
        '.ssh', '.aws', 'credentials', 'credentials.json', 'id_rsa', 'id_ed25519',
        '.netrc', '.npmrc', '.pypirc', 'secrets', 'secrets.json',
    } for part in path.parts)


def read_explicit(path):
    if forbidden(path) or '\x00' in str(path):
        raise ValueError('input_forbidden')
    # No symlinks: a harmless name must not redirect to a credential file.
    try:
        resolved = path.resolve()
    except RuntimeError:
        raise ValueError('input_forbidden') from None
    if path.is_symlink() or forbidden(resolved):
        raise ValueError('input_forbidden')
    if not stat.S_ISREG(path.stat().st_mode):
        raise ValueError('input_not_regular')
    with path.open('rb') as stream:
        data = stream.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES:
        raise ValueError('input_too_large')
    return data


def version(value):
    match = re.search(r'(?<![\w.])(\d{1,3}\.\d{1,3}\.\d{1,3})(?![\w.])',
                      value if isinstance(value, str) else '')
    return match.group(1) if match else 'unknown'


def timestamp(value):
    if not isinstance(value, str) or not re.fullmatch(
            r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:Z|[+-]\d{2}:\d{2})', value):
        return None
    try:
        return datetime.fromisoformat(value.replace('Z', '+00:00'))
    except ValueError:
        return None


def collect(request, base_dir):
    """Return safe manifest/summary from caller-supplied observations, not live proof."""
    sha = request.get('candidate_sha')
    stages = request.get('stages', {})
    if not isinstance(sha, str) or not re.fullmatch('[0-9a-f]{40}', sha):
        raise ValueError('invalid_candidate_sha')
    if not isinstance(stages, dict) or set(stages) - set(STAGES):
        raise ValueError('invalid_stages')
    system = request.get('system', {})
    if not isinstance(system, dict):
        system = {}
    manifest = {
        'schema_version': 1, 'candidate_sha': sha,
        'evidence_origin': 'caller_supplied_not_independently_verified',
        'system': {
            'os': 'Linux' if system.get('os') == 'Linux' else 'unknown',
            'release': version(system.get('release')),
            'architecture': system.get('architecture') if system.get('architecture')
                in ('x86_64', 'aarch64', 'armv7l', 'i686') else 'unknown',
        },
        'flutter_version': version(request.get('flutter_version')),
        'dart_version': version(request.get('dart_version')), 'stages': {},
    }
    for name in STAGES:
        result = {'status': 'unknown', 'error_code': 'input_missing'}
        supplied = stages.get(name)
        manifest['stages'][name] = result
        if not isinstance(supplied, dict):
            continue
        code = supplied.get('exit_code')
        code_valid = type(code) is int and 0 <= code <= 255
        result['exit_code'] = code if code_valid else None
        started, ended = timestamp(supplied.get('started_at')), timestamp(supplied.get('ended_at'))
        result['started_at'] = started.isoformat() if started else None
        result['ended_at'] = ended.isoformat() if ended else None
        command = supplied.get('command')
        command_valid = (isinstance(command, list) and bool(command)
                         and all(isinstance(token, str) for token in command)
                         and bool(command[0].strip()))
        if command_valid:
            result['command_sha256'] = hashlib.sha256(
                json.dumps(command, ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()
            # Preserve order/arity and common tooling tokens, redact all user material.
            safe = {'flutter', 'dart', 'test', 'build', 'linux', 'run', '--release',
                    '--debug', '--no-pub', '--fatal-infos', 'analyze'}
            result['command'] = [token if token in safe else '[redacted]' for token in command]
        outcomes = {}
        try:
            path = supplied.get('log')
            if not isinstance(path, str) or not path:
                raise ValueError('input_missing')
            data = read_explicit(Path(base_dir) / path)
            result.update(log_sha256=hashlib.sha256(data).hexdigest(), log_bytes=len(data))
            for line in data.decode('utf-8', errors='replace').splitlines():
                try:
                    row = json.loads(line)
                except (ValueError, RecursionError):
                    continue
                if (isinstance(row, dict) and type(row.get('evidence_version')) is int
                        and row['evidence_version'] == 1 and row.get('candidate_sha') == sha
                        and row.get('stage') == name and isinstance(row.get('case_id'), str)
                        and row.get('outcome') in ('passed', 'failed')):
                    outcomes.setdefault(row['case_id'], set()).add(row['outcome'])
            result['error_code'] = 'evidence_incomplete'
        except ValueError as error:
            result['error_code'] = str(error) if str(error) in {
                'input_forbidden', 'input_not_regular', 'input_too_large', 'input_missing',
            } else 'input_invalid'
        except OSError:
            result['error_code'] = 'input_unreadable'
        cases = supplied.get('expected_cases')
        cases_valid = (isinstance(cases, list) and bool(cases)
                       and all(isinstance(case, str) and bool(case) for case in cases)
                       and len(set(cases)) == len(cases))
        result['expected_count'] = len(cases) if cases_valid else 0
        result['passed_count'] = sum(outcomes.get(case) == {'passed'} for case in cases) if cases_valid else 0
        if (code_valid and code != 0) or any('failed' in value for value in outcomes.values()):
            result.update(status='failed', error_code='validation_failed')
        elif (code_valid and code == 0 and started and ended and ended >= started
              and command_valid and cases_valid and result['passed_count'] == len(cases)
              and manifest['system']['os'] == 'Linux'
              and manifest['system']['release'] != 'unknown'
              and manifest['system']['architecture'] != 'unknown'
              and all(manifest[key] != 'unknown' for key in ('flutter_version', 'dart_version'))):
            result.update(status='passed', error_code=None)
    interaction = manifest['stages']['linux_interaction']
    if interaction['status'] == 'passed' and manifest['stages']['linux_launch']['status'] != 'passed':
        interaction.update(status='unknown', error_code='launch_unverified')
    summary = '\n'.join([
        'Linux 验证证据（调用方提供，未独立核验）', '候选 SHA：' + sha,
        *(f'{label}：{manifest["stages"][name]["status"]}' for name, label in zip(STAGES, LABELS)),
        '原始日志仅留本机；unknown 表示证据不足。',
    ]) + '\n'
    return manifest, summary


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True, help='New local output directory')
    args = parser.parse_args(argv)
    try:
        request = json.loads(read_explicit(args.input))
        if not isinstance(request, dict):
            raise ValueError('invalid_input')
        manifest, summary = collect(request, args.input.absolute().parent)
        args.output.mkdir(parents=True, exist_ok=False)
        (args.output / 'manifest.json').write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        (args.output / 'summary.txt').write_text(summary, encoding='utf-8')
        print(summary, end='')
        return 0
    except (OSError, ValueError, RecursionError):
        print('证据包未生成：输入无效、不可读取或输出目录已存在。')
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
