from pathlib import Path
import os,sys,json,hashlib
root=Path(os.environ['BATCH4_ANDROID_SOURCE_ROOT'])
sys.path.insert(0,str(root/'experiments/redesign/android-rust-bridge-lab/checks'))
from linux_gate import run,sha,tracked_inputs
base=Path(os.environ['BATCH4_ANDROID_EVIDENCE']); evidence=base/'service';evidence.mkdir(exist_ok=False)
import subprocess
source=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
linux=base/'artifacts/linux'; work=base/'work/linux'; v=base/'verification'
binding=linux/'jvm/com/mightyoung/muyon/androidbridge/muyon_android_contract_bridge.kt'
lib=linux/'shipping/libmuyon_android_contract_bridge.so'; jar=evidence/'probe.jar';jna=work/'tools/jna.jar'
before=tracked_inputs();env=dict(os.environ)
result={'source':source,'source_sha':source,'Android_runtime':'NOT_RUN','classification':'INVALID'}
try:
 assert json.loads((linux/'verdict.json').read_text())['classification']=='GREEN'
 run(['bash',work/'tools/kotlinc/bin/kotlinc',binding,v/'ShippingServiceProbe.kt','-jvm-target','17','-classpath',jna,'-include-runtime','-d',jar],evidence/'compile.log',env)
 baseline=evidence/'baseline';baseline.mkdir()
 run(['java','-cp',str(jar)+':'+str(jna),'muyon.shippingverification.ShippingServiceProbe',source,lib,baseline],evidence/'baseline.log',env,timeout=90)
 run(['python3','-B',v/'verify_shipping_records.py','--runs',baseline/'runs.tsv','--source',source],evidence/'durable-oracle.log',env)
 run(['python3','-B','-m','unittest','discover','-s',v,'-p','test_verify_shipping_records.py'],evidence/'controls.log',dict(env,MUYON_SERVICE_BASELINE=str(baseline),MUYON_SERVICE_SOURCE=source,MUYON_SERVICE_SOURCE_ROOT=str(root)))
 result.update(classification='GREEN',library_sha256=sha(lib),jvm_binding_sha256=sha(binding),probe_sha256=sha(jar),probe_source_sha256=sha(v/'ShippingServiceProbe.kt'))
finally:
 result['source_inputs_unchanged']=before==tracked_inputs()
 if not result['source_inputs_unchanged']:
  result.update(classification='INVALID',failure='source_inputs_changed')
 (evidence/'verdict.json').write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps(result))

 if not result['source_inputs_unchanged']:
  raise RuntimeError('source_inputs_changed')
