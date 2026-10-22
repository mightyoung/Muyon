from pathlib import Path
import os,json,subprocess,shutil
r=Path('/workspace/muyon-ui-3aae');t=Path('/workspace/ui-shell-tools');o=t/'3aae';s=o/'smoke'
assert (o/'normal-assemble-exit.txt').read_text().strip()=='0'
cmd=json.loads((o/'product-command.json').read_text())['command'];cmd=[v for v in cmd if not v.startswith(':app:')];cmd+=['--init-script',str(s/'probe.init.gradle'),':app:assembleDebugAndroidTest']
e=dict(os.environ,JAVA_HOME=str(t/'jdk-17.0.21+9'),ANDROID_HOME=str(t/'sdk'),ANDROID_USER_HOME=str(t/'android-user'),GRADLE_USER_HOME=str(t/'gradle-cache'))
(s/'probe-command.json').write_text(json.dumps(cmd,indent=2)+'\n')
with (s/'probe-build.log').open('w') as f:x=subprocess.run(cmd,cwd=r,env=e,stdout=f,stderr=subprocess.STDOUT)
(s/'probe-build-exit.txt').write_text(str(x.returncode)+'\n');assert x.returncode==0
shutil.copy2(r/'apps/muyon_android/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk',s/'read-only-probe-androidTest.apk')
shutil.copy2(s/'original-source-androidTest.apk',r/'apps/muyon_android/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk')
