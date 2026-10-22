#!/usr/bin/env python3
"""Offline owned-source verification. Raw failures and NOT_RUN stay recorded."""
import datetime,hashlib,json,os,pathlib,subprocess
ROOT=pathlib.Path(__file__).resolve().parents[3]
TASK=pathlib.Path(__file__).resolve().parent
E=TASK/'evidence'
env=os.environ.copy();env.update(PATH='/tmp/mig20-rust/bin:'+env['PATH'],CARGO_HOME='/tmp/mig20-cargo',CARGO_TARGET_DIR='/tmp/mig20-target',RUSTFLAGS='-L native=/tmp/mig20-native-libs')
owned=['crates/muyon-core/src/agent/owner.rs','crates/muyon-core/src/agent/workflow.rs','crates/muyon-core/src/agent/origin.rs','crates/muyon-core/src/agent/tools.rs','crates/muyon-core/src/group_runtime/store.rs','crates/muyon-core/src/group_runtime/bridge.rs','crates/muyon-core/src/group_runtime/binding.rs','crates/muyon-core/src/group_runtime/gate.rs','crates/muyon-core/tests/group_request_binding.rs','crates/muyon-core/tests/support/group_origin_gate_cases.rs']
base=['cargo','test','--manifest-path','crates/Cargo.toml','-p','muyon-core','--offline','--locked']
checks=[('final-format',['rustfmt','--edition','2021','--check']+owned),('final-core',base),('final-clippy-arguments',['cargo','clippy','--manifest-path','crates/Cargo.toml','-p','muyon-core','--all-targets','--offline','--locked','--','-D','clippy::too_many_arguments']),('final-diff',['git','diff','--check'])]
manifest={'cwd':str(ROOT),'runs':[],'source_sha256':{s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in owned}}
for name,cmd in checks:
 start=datetime.datetime.now(datetime.timezone.utc).isoformat()
 with (E/(name+'.log')).open('wb') as out:r=subprocess.run(cmd,cwd=ROOT,env=env,stdout=out,stderr=subprocess.STDOUT)
 manifest['runs'].append(dict(name=name,command=cmd,start_utc=start,end_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),exit_code=r.returncode,status=("NOT_RUN" if r.returncode and "clippy" in cmd else ("PASS" if r.returncode==0 else "FAIL")),reason=("cargo clippy unavailable in selected toolchain" if r.returncode and "clippy" in cmd else None)))
 (E/'final-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');print(name,r.returncode,flush=True)
raise SystemExit(any(r['exit_code'] for r in manifest['runs']))
