#!/usr/bin/env python3
"""Keep runtime NOT_RUN separate from actual source SQL/static checks."""
import datetime
import hashlib
import pathlib
import re
import subprocess

repo = pathlib.Path(__file__).resolve().parents[4]
root = repo / 'docs/tasks/local-workspace-bot-provider-20261022'
lines = [datetime.datetime.now(datetime.timezone.utc).isoformat()]

def record(value):
    lines.append(value)
    (root / 'evidence/preparation-verification.log').write_text('\n'.join(lines) + '\n')

commands = [
    ['cargo', 'test', '--offline', '--locked', '--manifest-path', 'crates/Cargo.toml', '-p', 'muyon-core', '--test', 'bot_drafts'],
    ['cargo', 'test', '--offline', '--locked', '--manifest-path', 'crates/Cargo.toml', '-p', 'muyon-android-ffi', '--lib', 'local_draft_bridge_tests'],
    ['cargo', 'clippy', '--offline', '--locked', '--manifest-path', 'crates/Cargo.toml', '--workspace', '--all-targets', '--', '-D', 'warnings'],
    ['rustfmt', '--edition', '2021', '--check', 'crates/muyon-core/src/bot_drafts.rs', 'crates/muyon-core/tests/bot_drafts.rs', 'crates/muyon-android-ffi/src/lib.rs'],
]
for command in commands:
    record('$ ' + ' '.join(command))
    try:
        result = subprocess.run(command, cwd=repo, text=True, capture_output=True)
        record(f'exit={result.returncode}\n{result.stdout}{result.stderr}')
    except FileNotFoundError:
        record('NOT_RUN: executable absent; no software installed')
for command, cwd in [
    (['python3', str(root / 'evidence/preparation_sql_smoke.py')], repo),
    (['python3', str(root / 'evidence/sql_smoke.py')], repo),
    (['sha256sum', '-c', 'SHA256SUMS'], root / 'independent-verification'),
    (['git', 'diff', '--check'], repo),
    (['git', 'apply', '--check', str(root / 'CORE-EXPORT.patch')], repo),
]:
    result = subprocess.run(command, cwd=cwd, text=True, capture_output=True)
    record('$ ' + ' '.join(command))
    record(f'exit={result.returncode}\n{result.stdout}{result.stderr}')
    assert result.returncode == 0
core_tests = (repo / 'crates/muyon-core/tests/bot_drafts.rs').read_text()
ffi_source = (repo / 'crates/muyon-android-ffi/src/lib.rs').read_text()
assert len(re.findall(r'^#\[test\]', core_tests, re.M)) == 26
assert ffi_source.split('mod local_draft_bridge_tests {', 1)[1].count('#[test]') == 2
assert len(re.findall(r'^    pub fn local_draft_', ffi_source, re.M)) == 5
record('PASS source counts:26 core tests,2 FFI tests,5 native methods; no runtime PASS implied')
for path in ['crates/muyon-core/src/lib.rs', 'crates/Cargo.toml', 'crates/Cargo.lock']:
    old = subprocess.check_output(['git', 'show', '15c65c7c9c1f0af1e73c8092b2de2ac78939eea7:' + path], cwd=repo)
    assert old == (repo / path).read_bytes()
record('PASS sole-owned core export and dependency/lock files unchanged')
source = (repo / 'crates/muyon-core/src/bot_drafts.rs').read_text()
assert not re.search(r'\b(?:UPDATE|INSERT INTO|DELETE FROM)\s+(?:intents|business_grants|requests)\b', source)
assert '#[allow(' not in source
record('PASS no writes to existing generic intent/grant/request ledgers; no new lint allow')
for path in ['crates/muyon-core/src/bot_drafts.rs', 'crates/muyon-core/tests/bot_drafts.rs', 'crates/muyon-android-ffi/src/lib.rs']:
    record(hashlib.sha256((repo / path).read_bytes()).hexdigest() + '  ' + path)
record('NOT_RUN Kotlin/Service cold-recovery consumer, regenerated UniFFI, Android/device; HOLD remains')
print('\n'.join(lines))
