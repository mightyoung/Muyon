#!/usr/bin/env python3
"""Overlay only owned source files on a fixed B commit in a disposable archive."""
import datetime,hashlib,json,os,pathlib,shutil,subprocess,tarfile,tempfile
ROOT=pathlib.Path(__file__).resolve().parents[3];TASK=pathlib.Path(__file__).resolve().parent
PIN='863ece54c3d9ba0fc9900d71ec310a4764b9e1a4'
env=os.environ.copy();env.update(PATH='/tmp/mig20-rust/bin:'+env['PATH'],CARGO_HOME='/tmp/mig20-cargo',CARGO_TARGET_DIR='/tmp/mig20-target',RUSTFLAGS='-L native=/tmp/mig20-native-libs')
owned=['src/agent/owner.rs','src/agent/workflow.rs','src/group_runtime/store.rs','src/group_runtime/bridge.rs','src/group_runtime/binding.rs','tests/group_request_binding.rs']
manifest={'pin':PIN,'overlay':owned,'runs':[],'source_sha256':{s:hashlib.sha256((ROOT/'crates/muyon-core'/s).read_bytes()).hexdigest() for s in owned}}
with tempfile.TemporaryDirectory(prefix='mig20-canonical-B-') as tmp:
 tmp=pathlib.Path(tmp);archive=tmp/'source.tar';snap=tmp/'snapshot';snap.mkdir()
 with archive.open('wb') as out:subprocess.run(['git','archive',PIN],cwd=ROOT,stdout=out,check=True)
 with tarfile.open(archive) as source:source.extractall(snap,filter='data')
 core=snap/'crates/muyon-core'
 for name in owned:shutil.copyfile(ROOT/'crates/muyon-core'/name,core/name)
 # B's document owner is part of the real BusinessStore. Source harness needs its module.
 test=core/'tests/group_request_binding.rs';s=test.read_text();s=s.replace('#![allow(dead_code)]','#![allow(dead_code)]\n#[path = "../src/documents/mod.rs"]\nmod documents;');test.write_text(s)
 for label,args in [('tests',['test','--test','group_request_binding','--test','group_runtime_store','--test','group_runtime_bridge']),('clippy-arguments',['clippy','--all-targets'])]:
  cmd=['cargo',args[0],'--manifest-path',str(snap/'crates/Cargo.toml'),'-p','muyon-core','--offline','--locked']+args[1:]
  if args[0]=='clippy':cmd+=['--','-D','clippy::too_many_arguments']
  start=datetime.datetime.now(datetime.timezone.utc).isoformat()
  with (TASK/'evidence'/('combination-'+label+'.log')).open('wb') as out:r=subprocess.run(cmd,cwd=snap,env=env,stdout=out,stderr=subprocess.STDOUT)
  manifest['runs'].append(dict(name=label,command=cmd,start_utc=start,end_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),exit_code=r.returncode,status=("NOT_RUN" if r.returncode and "clippy" in cmd else ("PASS" if r.returncode==0 else "FAIL")),reason=("cargo clippy unavailable in selected toolchain" if r.returncode and "clippy" in cmd else None)));print(label,r.returncode,flush=True)
  (TASK/'evidence/combination-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
raise SystemExit(any(r['exit_code'] for r in manifest['runs']))
