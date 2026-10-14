"""Build an isolated field-order mutant from existing cached dependencies only."""
import hashlib, json, os, pathlib, shutil, subprocess, sys
lab=pathlib.Path(__file__).resolve().parents[1]
tools=pathlib.Path(os.environ['SPIKE_TOOLS']).resolve()
output=pathlib.Path(os.environ.get('SPIKE_EVIDENCE',str(tools/'mutation-evidence'))).resolve()
output.mkdir(parents=True,exist_ok=True)
source=tools/'mutation-source'
source.mkdir(exist_ok=True)
for name in ['Cargo.toml','Cargo.lock','rust-toolchain.toml']:shutil.copy2(lab/name,source/name)
shutil.copytree(lab/'src',source/'src',dirs_exist_ok=True)
p=source/'src/lib.rs';text=p.read_text()
old="    observer:Option<Arc<dyn LabObserver>>,\n    _callback:CallbackGuard,\n    _call:CallGuard<'a>,"
new="    _call:CallGuard<'a>,\n    observer:Option<Arc<dyn LabObserver>>,\n    _callback:CallbackGuard,"
assert text.count(old)==1
p.write_text(text.replace(old,new))
env={**os.environ,'CARGO_HOME':str(tools/'cargo'),'RUSTUP_HOME':str(tools/'rustup'),'CARGO_TARGET_DIR':str(tools/'mutation-target'),'PATH':str(tools/'cargo/bin')+os.pathsep+os.environ['PATH']}
command=['cargo','build','--offline','--locked','--release','--lib','--manifest-path',str(source/'Cargo.toml')]
with (output/'mutation-build.log').open('w') as log:
 result=subprocess.run(command,env=env,stdout=log,stderr=subprocess.STDOUT)
assert result.returncode==0,result.returncode
bindings=tools/'mutation-generated';bindings.mkdir(exist_ok=True)
shutil.copy2(tools/'generated/spike01_bridge_lab.py',bindings/'spike01_bridge_lab.py')
shutil.copy2(tools/'mutation-target/release/libspike01_bridge_lab.so',bindings/'libspike01_bridge_lab.so')
records=[{'command':command,'exit':result.returncode}]
for method in ['close_session','unsubscribe']:
 command=['timeout','8s',sys.executable,'-B',str(lab/'tests/probe_h1.py'),method,'pause']
 proc=subprocess.run(command,env={**env,'PYTHONPATH':str(bindings)},capture_output=True,text=True)
 (output/f'mutation-{method}.log').write_text(proc.stdout+proc.stderr)
 assert proc.returncode==1,(method,proc.returncode)
 assert 'AssertionError: (False, True,' in proc.stderr,(method,proc.stderr)
 records.append({'command':command,'exit':proc.returncode,'expected':'detected missing native wait / premature return'})
for name,path in [('mutant_source',p),('mutant_library',bindings/'libspike01_bridge_lab.so'),('binding',bindings/'spike01_bridge_lab.py'),('probe',lab/'tests/probe_h1.py')]:
 records.append({'component':name,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
(output/'mutation-results.json').write_text(json.dumps(records,indent=2))
print('PASS early counter mutation detected for close_session and unsubscribe; both child exits1')
