from pathlib import Path
import os,subprocess,json
r=Path('/workspace/muyon-ui-3aae');t=Path('/workspace/ui-shell-tools');o=t/'3aae'
e=dict(os.environ,JAVA_HOME=str(t/'jdk-17.0.21+9'),ANDROID_HOME=str(t/'sdk'),ANDROID_USER_HOME=str(t/'android-user'),GRADLE_USER_HOME=str(t/'gradle-cache'),CARGO_HOME=str(t/'cargo'),RUSTUP_HOME=str(t/'rustup'),MUYON_NATIVE_OUTPUT=str(o/'native'),MUYON_ML_OUTPUT=str(o/'ml'),MUYON_LLAMA_ARCHIVE=str(t/'candidate-product-ml/llama-b11763.tar.gz'),LIBRARY_PATH=str(t/'host-link-libs'))
e['PATH']=str(t/'cargo/bin')+':'+e['JAVA_HOME']+'/bin:'+e['PATH']
def run(name,cmd,cwd=r,env=e):
 print('START',name,flush=True)
 with (o/(name+'.log')).open('w') as f:x=subprocess.run(cmd,cwd=cwd,env=env,stdout=f,stderr=subprocess.STDOUT)
 (o/(name+'-exit.txt')).write_text(str(x.returncode)+'\n');print('END',name,x.returncode,flush=True);assert x.returncode==0,name
run('model-offline',['python3','-B','apps/muyon_android/checks/ci_model_inputs.py',str(t/'candidate-model-source'),str(t/'candidate-model-assets')])
run('native-build',['sh','apps/muyon_android/build-native.sh'])
b=dict(e,CARGO_TARGET_DIR=str(o/'bindings-target'))
run('binding-build',['cargo','+1.93.1','build','--offline','--locked','--manifest-path','crates/Cargo.toml','-p','muyon-android-ffi','--features','bindings'],env=b)
run('binding-generate',[str(o/'bindings-target/debug/uniffi-bindgen'),'generate','--library',str(o/'bindings-target/debug/libmuyon_android_product.so'),'--language','kotlin','--config','muyon-android-ffi/uniffi.android.toml','--out-dir',str(o/'generated')],cwd=r/'crates',env=b)
run('binding-cmp',['cmp',str(o/'generated/com/mightyoung/muyon/productbridge/muyon_android_product.kt'),str(r/'apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/productbridge/muyon_android_product.kt')])
bid=(o/'native/build-id.txt').read_text().strip()
cmd=[str(t/'gradle-8.13/bin/gradle'),'--offline','--no-daemon','--console=plain','--init-script',str(t/'maven-offline-restore/local.init.gradle'),'-p','apps/muyon_android','-PmuyonProductNativeInputs='+str(o/'native/jni'),'-PmuyonModelAssets='+str(t/'candidate-model-assets'),'-PmuyonSource='+bid,':app:clean',':app:assembleDebug',':app:assembleDebugAndroidTest',':app:lintDebug']
(o/'product-command.json').write_text(json.dumps({'source_sha':'3aae195c088f1b943be897efc7d874974066d79a','build_id':bid,'command':cmd},indent=2))
run('product-build',cmd)
