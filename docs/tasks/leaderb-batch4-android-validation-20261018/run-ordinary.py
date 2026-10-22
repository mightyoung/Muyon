from pathlib import Path
import os,sys,json,shutil,subprocess,zipfile,hashlib
root=Path(os.environ['BATCH4_ANDROID_SOURCE_ROOT']); sys.path.insert(0,str(root/'experiments/redesign/android-rust-bridge-lab/checks'))
from linux_gate import run,sha,tracked_inputs
base=Path(os.environ['BATCH4_ANDROID_EVIDENCE']);e=base/'ordinary';e.mkdir();ui=root/'experiments/redesign/android-compose-lab'
gradle=base/'work/package/gradle-8.13/bin/gradle'; cache=base/'work/package/gradle-cache'
env=dict(os.environ,MUYON_UI_GRADLE=str(gradle),MUYON_UI_GRADLE_HOME=str(cache),GRADLE_USER_HOME=str(cache))
before=tracked_inputs();result={'classification':'INVALID','Android_runtime':'NOT_RUN','native_inputs_supplied':False}
try:
 run([gradle,'--no-daemon','--console=plain','-p',ui,':app:clean',':state:clean'],e/'clean.log',env,cwd=ui,timeout=300)
 run(['bash',ui/'run-ci-checks.sh'],e/'build.log',env,cwd=ui,timeout=1200)
 apks={}
 for name,path in [('app-debug.apk',ui/'app/build/outputs/apk/debug/app-debug.apk'),('app-debug-androidTest.apk',ui/'app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk')]:
  shutil.copyfile(path,e/name)
  with zipfile.ZipFile(path) as z:
   natives={n:hashlib.sha256(z.read(n)).hexdigest() for n in z.namelist() if n.startswith('lib/') and n.endswith('.so')}
  assert not any('libmuyon_android_contract_bridge.so' in n for n in natives)
  apks[name]={'sha256':sha(path),'native_entries':natives}
 result.update(classification='GREEN',source_sha=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),artifacts=apks)
finally:
 result['source_inputs_unchanged']=before==tracked_inputs()
 if not result['source_inputs_unchanged']:
  result.update(classification='INVALID',failure='source_inputs_changed')
 (e/'verdict.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))

 if not result['source_inputs_unchanged']:
  raise RuntimeError('source_inputs_changed')
