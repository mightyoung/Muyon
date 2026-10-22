#!/usr/bin/env python3
"""Verify available checks; explicitly retain unavailable Rust checks as NOT_RUN."""
import datetime
import hashlib
import pathlib
import re
import shutil
import subprocess

repo = pathlib.Path(__file__).resolve().parents[4]
root = repo / 'docs/tasks/local-workspace-bot-provider-20261022'
lines = [datetime.datetime.now(datetime.timezone.utc).isoformat()]

def record(text):
    lines.append(text)
    (root / 'evidence/null-fix-verification.log').write_text('\n'.join(lines) + '\n')

for tool in ['cargo', 'rustc', 'rustfmt']:
    record(f'{tool}: {shutil.which(tool) or "NOT_FOUND"}')
for path in ['/tmp/muyon-rust/bin', '/tmp/muyon-cargo', '/tmp/muyon-native-libs', '/tmp/muyon-document-cargo-target']:
    record(f'{path}: {"EXISTS" if pathlib.Path(path).exists() else "ABSENT"}')
commands = [
    ['cargo', 'test', '--offline', '--locked', '--manifest-path', 'crates/Cargo.toml', '-p', 'muyon-core', '--test', 'bot_drafts'],
    ['cargo', 'test', '--offline', '--locked', '--manifest-path', 'crates/Cargo.toml', '-p', 'muyon-android-ffi', '--lib', 'local_draft_bridge_tests'],
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
    (['sha256sum', '-c', 'SHA256SUMS'], root / 'independent-verification'),
    (['python3', str(root / 'evidence/sql_smoke.py')], repo),
    (['git', 'apply', '--check', str(root / 'CORE-EXPORT.patch')], repo),
    (['git', 'diff', '--check'], repo),
]:
    result = subprocess.run(command, cwd=cwd, text=True, capture_output=True)
    record('$ ' + ' '.join(command))
    record(f'exit={result.returncode}\n{result.stdout}{result.stderr}')
    assert result.returncode == 0
old = subprocess.check_output(['git', 'show', '7ca2bd4e9edf9cd0952ce784d3f85561583537db:crates/muyon-android-ffi/src/lib.rs'], cwd=repo, text=True)
new = (repo / 'crates/muyon-android-ffi/src/lib.rs').read_text()
# rustfmt also inserts optional trailing commas, not only whitespace.
def normalize(source):
    return re.sub(r',([})\]])', r'\1', re.sub(r'\s+', '', source))
assert normalize(old) == normalize(new)
record('PASS FFI formatting-only changes: whitespace and optional trailing commas; no interface/behavior change')
assert len(re.findall(r'^#\[test\]', (repo / 'crates/muyon-core/tests/bot_drafts.rs').read_text(), re.M)) == 19
record('19 provider tests in source; repaired-source Rust NOT_RUN, not 19 PASS')
record('Original authoritative history: targeted1 PASS/14 FAIL; partial core104 PASS/14 FAIL; FFI BLOCKED; scoped fmt3 FAIL')
for path in ['crates/muyon-core/src/bot_drafts.rs', 'crates/muyon-core/tests/bot_drafts.rs', 'crates/muyon-android-ffi/src/lib.rs', 'crates/muyon-core/src/lib.rs', 'crates/Cargo.toml', 'crates/Cargo.lock']:
    record(hashlib.sha256((repo / path).read_bytes()).hexdigest() + '  ' + path)
print('\n'.join(lines))
