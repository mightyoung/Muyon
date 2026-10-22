#!/usr/bin/env python3
"""Compile real core/evidence sources together without editing the core-owned lib.rs.
The generated entrypoint only declares the exact modules of lib.rs plus evidence.
No source is rewritten, no dependencies/permissions installed or broadened.
"""
import argparse
import hashlib
import json
import pathlib
import re
import shutil
import subprocess
import tempfile
import tomllib

p = argparse.ArgumentParser()
p.add_argument('--repo', required=True, type=pathlib.Path)
p.add_argument('--filter', default='evidence::store::tests')
p.add_argument('--cargo', default='cargo')
p.add_argument('--full-core', action='store_true')
a = p.parse_args()
repo = a.repo.resolve()
core = repo / 'crates/muyon-core'
workspace = tomllib.loads((repo / 'crates/Cargo.toml').read_text())
manifest = tomllib.loads((core / 'Cargo.toml').read_text())
root = pathlib.Path(tempfile.mkdtemp(prefix='muyon-evidence-store-harness-'))
lines = ['[package]', 'name = "muyon-core"', 'version = "0.1.0"', 'edition = "2021"',
         '[lib]', 'path = "lib.rs"', '[dependencies]']
for name, value in manifest['dependencies'].items():
    value = dict(value)
    if value.pop('workspace', False):
        inherited = workspace['workspace']['dependencies'][name]
        value = {'version': inherited} if isinstance(inherited, str) else dict(inherited)
    if 'path' in value:
        value['path'] = str((core / value['path']).resolve())
    fields = ', '.join(f'{k} = {json.dumps(v)}' for k, v in value.items())
    lines.append(f'{name} = {{ {fields} }}')
lines.extend(['[target.\'cfg(target_os = "android")\'.dependencies]',
              'libsqlite3-sys = { version = "=0.35.0", features = ["bundled"] }',
              '[profile.dev]', 'debug = 0', 'incremental = false'])
for file in sorted((core / 'tests').glob('*.rs')):
    lines.extend(['[[test]]', f'name = {json.dumps(file.stem)}',
                  f'path = {json.dumps(str(file))}'])
for file in sorted((core / 'src/bin').glob('*.rs')):
    lines.extend(['[[bin]]', f'name = {json.dumps(file.stem)}',
                  f'path = {json.dumps(str(file))}'])
(root / 'Cargo.toml').write_text('\n'.join(lines) + '\n')
shutil.copyfile(repo / 'crates/Cargo.lock', root / 'Cargo.lock')
module_specs = re.findall(r'^(pub )?mod (\w+);', (core / 'src/lib.rs').read_text(), re.M)
if not any(name == 'evidence' for _, name in module_specs):
    module_specs.append(('pub ', 'evidence'))
entry = []
for visibility, name in module_specs:
    file = core / 'src' / (name + '.rs')
    if not file.is_file():
        file = core / 'src' / name / 'mod.rs'
    assert file.is_file(), file
    entry.append(f'#[path = {json.dumps(str(file))}] {visibility}mod {name};')
(root / 'lib.rs').write_text('\n'.join(entry) + '\n')
sha = subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD'], text=True).strip()
print('Actual source checkout:', sha, flush=True)
source_files = sorted((core / 'src').rglob('*.rs')) + sorted((core / 'tests').rglob('*.rs'))
bindings = [(str(file.relative_to(core)), hashlib.sha256(file.read_bytes()).hexdigest())
            for file in source_files]
print('Actual Rust source manifest SHA256:',
      hashlib.sha256(json.dumps(bindings, separators=(',', ':')).encode()).hexdigest(), flush=True)
print('Runner SHA256:', hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest(), flush=True)
print('Generated module-only harness:', root, flush=True)
# Leaving the original workspace prunes unrelated workspace-only lock entries.
# Resolve offline and refuse every version/source/checksum outside the fixed lock.
subprocess.run([a.cargo, 'metadata', '--offline', '--format-version', '1',
                '--manifest-path', str(root / 'Cargo.toml')], check=True,
               stdout=subprocess.DEVNULL)
def packages(lock):
    return {(x['name'], x['version'], x.get('source'), x.get('checksum'))
            for x in tomllib.loads(lock.read_text())['package']}
assert packages(root / 'Cargo.lock') <= packages(repo / 'crates/Cargo.lock'), 'dependency drift'
print('All harness dependencies match repository lock versions/sources/checksums', flush=True)
command = [a.cargo, 'test', '--locked', '--offline', '--manifest-path', str(root / 'Cargo.toml')]
if not a.full_core:
    command.extend(['--lib', a.filter])
raise SystemExit(subprocess.run(command).returncode)
