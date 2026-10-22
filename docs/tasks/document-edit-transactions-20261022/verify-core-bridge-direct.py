#!/usr/bin/env python3
"""Explicit library-only fallback; does not claim cargo integration/bin gate passes.
Input is an exact temporary combination produced by verify-durable-combination.sh.
No source edits, dependency downloads, engine execution or test-result fabrication.
"""
import json,os,pathlib,subprocess,sys,tempfile
archive=pathlib.Path(sys.argv[1]).resolve()
out=pathlib.Path(tempfile.mkdtemp(prefix='muyon-core-bridge-direct.'))
print('Exact input archive:',archive,flush=True);print('Direct test evidence:',out,flush=True)
cmd=[os.environ.get('CARGO','cargo'),'build','--offline','--locked','--manifest-path',str(archive/'crates/Cargo.toml'),'-p','muyon-core','--lib','--message-format=json']
print('Command:',repr(cmd),flush=True)
p=subprocess.run(cmd,capture_output=True,text=True)
(out/'build.jsonl').write_text(p.stdout);(out/'build.stderr.log').write_text(p.stderr)
print(p.stderr,end='',flush=True)
if p.returncode:sys.exit(p.returncode)
artifacts={}
for line in p.stdout.splitlines():
 try:r=json.loads(line)
 except ValueError:continue
 if r.get('reason')=='compiler-artifact':
  libs=[x for x in r['filenames'] if x.endswith('.rlib')]
  if libs:artifacts[r['target']['name']]=libs[0]
cmd=[os.environ.get('RUSTC','rustc'),'--edition=2021','--test',str(archive/'crates/muyon-core/tests/document_edit_core_bridge.rs'),'-L','dependency='+str(pathlib.Path(artifacts['serde_json']).parent),'-L','native=/workspace/document-edit-tools/native','--extern','muyon_core='+artifacts['muyon_core'],'--extern','serde_json='+artifacts['serde_json'],'-o',str(out/'bridge-tests')]
print('Command:',repr(cmd),flush=True)
p=subprocess.run(cmd,capture_output=True,text=True);(out/'compile.log').write_text(p.stdout+p.stderr);print(p.stdout+p.stderr,end='',flush=True)
if p.returncode:sys.exit(p.returncode)
cmd=[str(out/'bridge-tests'),'--nocapture'];print('Command:',repr(cmd),flush=True)
p=subprocess.run(cmd,capture_output=True,text=True);(out/'tests.log').write_text(p.stdout+p.stderr);print(p.stdout+p.stderr,end='',flush=True);sys.exit(p.returncode)
