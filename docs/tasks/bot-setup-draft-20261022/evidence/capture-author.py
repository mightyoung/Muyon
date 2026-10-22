#!/usr/bin/env python3
"""Offline baseline and behavioral mutation capture. Writes only --output and /tmp."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--compiler', required=True)
parser.add_argument('--output', required=True)
args = parser.parse_args()
root = Path(subprocess.check_output(['git', 'rev-parse', '--show-toplevel'], text=True).strip())
out = Path(args.output).resolve()
out.mkdir(parents=True, exist_ok=True)
compiler = str(Path(args.compiler).resolve())
source = root / 'apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/agents/setup/BotSetupDraft.kt'
tests = root / 'apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/agents/setup/BotSetupDraftChecks.kt'
runner = tests.parent / 'run-offline-checks.sh'

def now():
    return datetime.now(timezone.utc).isoformat()

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

metadata = {
    'record_type': 'NEW offline rerun; not recovered original GREEN/mutation output',
    'actor': 'author', 'started_utc': now(), 'cwd': str(root),
    'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
    'platform': platform.platform(), 'python_version': platform.python_version(),
    'inputs_sha256': {str(p.relative_to(root)): sha(p) for p in [source, tests, runner]},
    'commands': [],
}
zip_file = Path(compiler).parents[2] / 'kotlin.zip'
if zip_file.exists():
    metadata['compiler_archive_sha256'] = sha(zip_file)

def capture(label, command, env=None):
    start = now()
    result = subprocess.run(command, cwd=root, env=env, capture_output=True)
    (out / (label + '.stdout.log')).write_bytes(result.stdout)
    (out / (label + '.stderr.log')).write_bytes(result.stderr)
    metadata['commands'].append({'label': label, 'argv': command,
        'started_utc': start, 'ended_utc': now(), 'exit_code': result.returncode})
    return result.returncode

assert capture('java-version', ['java', '-version']) == 0
assert capture('kotlin-version', [compiler, '-version']) == 0
env = os.environ.copy()
env['KOTLINC'] = compiler
metadata['baseline_environment_override'] = {'KOTLINC': compiler}
assert capture('baseline', [str(runner)], env) == 0
original = source.read_text()
mutations = {
    'late-result': ('if (cancelled || token != request || token.revision != revision) return false', 'if (cancelled) return false'),
    'user-lock': ('|| role.userLocked', ''),
    'unknown-unfreeze': ('require(!cancelled && creation.status in setOf(CreationStatus.NOT_REQUESTED, CreationStatus.REJECTED))', 'require(!cancelled)'),
    'unconfirmed-review': ('require(invalidations.isEmpty())', 'require(true)'),
    'cross-scope': ('require(allowedMaterials.all { it.id.isNotBlank() && it.scope == scope })', 'require(allowedMaterials.all { it.id.isNotBlank() })'),
}
metadata['mutations'] = []
with tempfile.TemporaryDirectory(prefix='bot-setup-audit-') as temporary:
    for label, (before, after) in mutations.items():
        count = original.count(before)
        assert count > 0
        folder = Path(temporary) / label
        folder.mkdir()
        modified = folder / 'BotSetupDraft.kt'
        modified.write_text(original.replace(before, after))
        jar = folder / 'checks.jar'
        compile_code = capture(label + '-compile', [compiler, str(modified), str(tests), '-include-runtime', '-d', str(jar)])
        assert compile_code == 0, label + ' must compile before behavioral check'
        run_code = capture(label + '-run', ['java', '-jar', str(jar)])
        assert run_code != 0, label + ' survived'
        metadata['mutations'].append({'label': label, 'replace_before': before,
            'replace_after': after, 'replacement_count': count,
            'mutated_source_sha256': sha(modified), 'compile_exit_code': compile_code,
            'run_exit_code': run_code, 'outcome': 'KILLED by behavioral assertion'})
        print(label + ': KILLED by behavioral assertion', flush=True)
metadata['ended_utc'] = now()
metadata['output_sha256'] = {p.name: sha(p) for p in sorted(out.glob('*.log'))}
(out / 'metadata.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n')
print('PASS baseline 11 groups and five compiled behavioral mutations')
