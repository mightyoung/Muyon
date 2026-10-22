from pathlib import Path
import subprocess,os,json,hashlib
root=Path('/workspace/ui-shell-tools');out=root/'3aae';repo=Path('/workspace/muyon-ui-3aae');assert (out/'product-build-exit.txt').read_text().strip()=='0';env=dict(os.environ,ANDROID_HOME=str(root/'sdk'),JAVA_HOME=str(root/'jdk-17.0.21+9'));apk=repo/'apps/muyon_android/app/build/outputs/apk/debug/app-debug.apk';native=out/'native/jni';gen=out/'generated/com/mightyoung/muyon/productbridge/muyon_android_product.kt';checked=repo/'apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/productbridge/muyon_android_product.kt'
for name,cmd in [('package.json',['python3','-B','apps/muyon_android/checks/package_gate.py',str(apk),str(native),str(gen),str(checked)]),('model-package.json',['python3','-B','apps/muyon_android/checks/model_package_gate.py',str(apk),str(root/'candidate-model-assets'),str(native)]),('signature.log',[str(root/'sdk/build-tools/35.0.0/apksigner'),'verify','--verbose','--print-certs',str(apk)]),('badging.log',[str(root/'sdk/build-tools/35.0.0/aapt'),'dump','badging',str(apk)])]:
 r=subprocess.run(cmd,cwd=repo,env=env,capture_output=True,text=True);(out/name).write_text(r.stdout+r.stderr);assert r.returncode==0,r.stderr;print(name,'PASS',flush=True)
items=[]
for p in [apk,repo/'apps/muyon_android/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk']:
 items.append({'path':str(p),'size_bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
(out/'artifacts.json').write_text(json.dumps({'source_sha':'3aae195c088f1b943be897efc7d874974066d79a','build_id':(out/'native/build-id.txt').read_text().strip(),'artifacts':items},indent=2)+'\n');print(json.dumps(items,indent=2))
