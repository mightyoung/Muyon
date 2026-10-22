#!/usr/bin/env python3
"""Real-library integration fallback only; it does not clear a broken worker build."""
import json,os,pathlib,subprocess,sys,tempfile
repo=pathlib.Path(sys.argv[1]).resolve();out=pathlib.Path(tempfile.mkdtemp(prefix='muyon-source-tail-direct.'))
print('Source:',repo,'\nEvidence:',out,flush=True)
cmd=[os.environ.get('CARGO','cargo'),'build','--offline','--locked','--manifest-path',str(repo/'crates/Cargo.toml'),'-p','muyon-core','--lib','--message-format=json']
print(repr(cmd),flush=True);p=subprocess.run(cmd,capture_output=True,text=True);(out/'build.jsonl').write_text(p.stdout);(out/'build.stderr.log').write_text(p.stderr);print(p.stderr,end='',flush=True)
if p.returncode:sys.exit(p.returncode)
libs={}
for line in p.stdout.splitlines():
 try:v=json.loads(line)
 except ValueError:continue
 if v.get('reason')=='compiler-artifact':
  r=[f for f in v['filenames'] if f.endswith('.rlib')]
  if r:libs[v['target']['name']]=r[0]
cmd=[os.environ.get('RUSTC','rustc'),'--edition=2021','--test',str(repo/'crates/muyon-core/tests/document_edit_gateway.rs'),'-L','dependency='+str(pathlib.Path(libs['serde_json']).parent),'-L','native=/workspace/document-edit-tools/native']
for name in ['muyon_core','serde_json','sha2']:cmd+=['--extern',name+'='+libs[name]]
cmd+=['-o',str(out/'gateway-tests')];print(repr(cmd),flush=True);p=subprocess.run(cmd,capture_output=True,text=True);(out/'compile.log').write_text(p.stdout+p.stderr);print(p.stdout+p.stderr,end='',flush=True)
if p.returncode:sys.exit(p.returncode)
cmd=[str(out/'gateway-tests'),*sys.argv[2:],'--nocapture'];print(repr(cmd),flush=True);p=subprocess.run(cmd,capture_output=True,text=True);(out/'tests.log').write_text(p.stdout+p.stderr);print(p.stdout+p.stderr,end='',flush=True);sys.exit(p.returncode)
