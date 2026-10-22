#!/usr/bin/env python3
"""Reproduce offline verification with explicit statuses, hashes and tool paths."""
import datetime, hashlib, json, os, pathlib, subprocess
ROOT = pathlib.Path(__file__).resolve().parents[3]
EVIDENCE = pathlib.Path(__file__).resolve().parent / 'evidence'
TOOLCHAIN = pathlib.Path('/tmp/mig20-rust/bin')
env = os.environ.copy()
env.update(PATH=str(TOOLCHAIN)+':'+env['PATH'], CARGO_HOME='/tmp/mig20-cargo', CARGO_TARGET_DIR='/tmp/mig20-target', RUSTFLAGS='-L native=/tmp/mig20-native-libs')
checks = [
 ('final-rustc', [str(TOOLCHAIN/'rustc'), '--version', '--verbose']),
 ('final-runtime-compile', [str(TOOLCHAIN/'rustc'), '--edition=2021', '-D', 'warnings', '--test', 'crates/muyon-core/tests/group_runtime.rs', '-o', '/tmp/mig20-final-runtime']),
 ('final-runtime', ['/tmp/mig20-final-runtime']),
 ('final-governance-compile', [str(TOOLCHAIN/'rustc'), '--edition=2021', '-D', 'warnings', '--test', 'crates/muyon-core/tests/group_governance.rs', '-o', '/tmp/mig20-final-governance']),
 ('final-governance', ['/tmp/mig20-final-governance']),
 ('final-format', [str(TOOLCHAIN/'rustfmt'), '--edition', '2021', '--check', 'crates/muyon-core/src/group_runtime/mod.rs', 'crates/muyon-core/tests/group_runtime.rs']),
 ('final-cargo', [str(TOOLCHAIN/'cargo'), 'test', '--manifest-path', 'crates/Cargo.toml', '-p', 'muyon-core', '--locked', '--offline']),
 ('final-diff', ['git', 'diff', '--check']),
]
manifest={'cwd':str(ROOT),'environment':{k:env[k] for k in ['CARGO_HOME','CARGO_TARGET_DIR','RUSTFLAGS']},'runs':[]}
failed_compile=set()
for name,command in checks:
    dependency={'final-runtime':'final-runtime-compile','final-governance':'final-governance-compile'}.get(name)
    if dependency in failed_compile:
        manifest['runs'].append({'name':name,'status':'NOT_RUN','reason':'compile failed; stale binary must not run'})
        continue
    start=datetime.datetime.now(datetime.timezone.utc).isoformat()
    with (EVIDENCE/(name+'.stdout.log')).open('wb') as out, (EVIDENCE/(name+'.stderr.log')).open('wb') as err:
        result=subprocess.run(command,cwd=ROOT,env=env,stdout=out,stderr=err)
    manifest['runs'].append({'name':name,'command':command,'start_utc':start,'end_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'exit_code':result.returncode})
    if result.returncode and name.endswith('-compile'): failed_compile.add(name)
    print(name,result.returncode,flush=True)
    (EVIDENCE/'final-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
manifest['sha256']={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [ROOT/'crates/muyon-core/src/group_runtime/mod.rs',ROOT/'crates/muyon-core/tests/group_runtime.rs',ROOT/'crates/muyon-core/src/group_governance/mod.rs',ROOT/'crates/Cargo.lock']}
(EVIDENCE/'final-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
raise SystemExit(any(r.get('exit_code',1)!=0 for r in manifest['runs']))
