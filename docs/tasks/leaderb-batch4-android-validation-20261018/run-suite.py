from pathlib import Path
import subprocess,os,json,sys,hashlib,shutil
root=Path(sys.argv[1]).resolve();base=Path(sys.argv[2]).resolve();runners=Path(__file__).resolve().parent;source=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip();checks=root/'experiments/redesign/android-rust-bridge-lab/checks';env=dict(os.environ,BATCH4_ANDROID_EVIDENCE=str(base),BATCH4_ANDROID_SOURCE_ROOT=str(root));base.mkdir(exist_ok=True,parents=True)
(base/'verification').mkdir(exist_ok=True)
for name in ['ShippingServiceProbe.kt','verify_shipping_records.py','test_verify_shipping_records.py']:
 shutil.copyfile(runners/name,base/'verification'/name)
rows=[]
def stage(label,command,cwd=root):
 log=base/(label+'-runner.log')
 with log.open('w') as f:r=subprocess.run([str(x) for x in command],cwd=cwd,env=env,stdout=f,stderr=subprocess.STDOUT)
 (base/(label+'-runner.exit')).write_text(str(r.returncode)+'\n');rows.append(dict(stage=label,exit=r.returncode));(base/'progress.json').write_text(json.dumps(dict(source_sha=source,stages=rows),indent=2)+'\n');print(label,r.returncode,flush=True);return r.returncode==0
for abi in ['arm64-v8a','x86_64']:
 stage(abi,['python3','-B',checks/'android_gate.py','--abi',abi,'--evidence-dir',base/'artifacts'/abi,'--work-dir',base/'work'/abi])
stage('linux',['python3','-B',checks/'linux_gate.py','--mode','full','--evidence-dir',base/'artifacts/linux','--work-dir',base/'work/linux'])
stage('service',['python3','-B',runners/'run-shipping.py'])
if (base/'service/probe.jar').exists() and (base/'artifacts/linux/shipping/libmuyon_android_contract_bridge.so').exists():
 sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
 (base/'shipping-contract.json').write_text(json.dumps(dict(source_sha=source,probe_jar_sha256=sha(base/'service/probe.jar'),library_sha256=sha(base/'artifacts/linux/shipping/libmuyon_android_contract_bridge.so')),indent=2)+'\n')
 stage('service-inverses',['python3','-B',runners/'same_source_shipping_inverses.py','--source-root',root,'--evidence-dir',base/'service-inverses','--work-dir',base/'work/service-inverses','--probe-jar',base/'service/probe.jar','--baseline-lib',base/'artifacts/linux/shipping/libmuyon_android_contract_bridge.so','--java',Path(env['JAVA_HOME'])/'bin/java','--jna',base/'work/linux/tools/jna.jar'])
stage('service-private',['env','CARGO_TARGET_DIR='+str(base/'work/service-private-target'),'MUYON_BRIDGE_BUILD_ID='+source,'cargo','test','--offline','--locked','--release','--manifest-path',root/'experiments/redesign/rust-agent-host-lab/core/Cargo.toml','--test','service_oracle','--test','service_runtime','--test','service_lifecycle','--test','service_controller','--test','service_root'])
stage('package',['python3','-B',checks/'package_gate.py','--artifacts',base/'artifacts','--evidence-dir',base/'package','--work-dir',base/'work/package'])
# Preserve compiler/lint output before ordinary clean overwrites diagnostic state.
ui_build=root/'experiments/redesign/android-compose-lab/app/build'
retained=base/'package/build-evidence';inventory=[]
for pattern in ['reports/lint-results-debug.*','generated/aidl_source_output_dir/debug/out/**/*.java']:
 for path in sorted(ui_build.glob(pattern)):
  relative=path.relative_to(ui_build);destination=retained/relative;destination.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(path,destination)
  inventory.append(dict(path=str(relative),sha256=hashlib.sha256(destination.read_bytes()).hexdigest()))
retained.mkdir(parents=True,exist_ok=True)
(retained/'inventory.json').write_text(json.dumps(inventory,indent=2)+'\n')
stage('ordinary',['python3','-B',runners/'run-ordinary.py'])
stage('controls',['python3','-B','-m','unittest','discover','-s',checks,'-p','test_*.py'])
print('ALL_STAGES_STOPPED',flush=True)
