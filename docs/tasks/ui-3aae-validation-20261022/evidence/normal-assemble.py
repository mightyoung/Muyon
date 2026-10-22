from pathlib import Path
import os,subprocess,json
r=Path('/workspace/muyon-ui-3aae');t=Path('/workspace/ui-shell-tools');o=t/'3aae'
assert (o/'product-build-exit.txt').read_text().strip()=='0'
m=json.loads((o/'product-command.json').read_text());cmd=m['command'];cmd=[v for v in cmd if v not in ['--offline',':app:clean',':app:assembleDebugAndroidTest',':app:lintDebug']]
e=dict(os.environ,JAVA_HOME=str(t/'jdk-17.0.21+9'),ANDROID_HOME=str(t/'sdk'),ANDROID_USER_HOME=str(t/'android-user'),GRADLE_USER_HOME=str(t/'gradle-cache'))
(o/'normal-command.json').write_text(json.dumps(cmd,indent=2)+'\n')
with (o/'normal-assemble.log').open('w') as f:x=subprocess.run(cmd,cwd=r,env=e,stdout=f,stderr=subprocess.STDOUT)
(o/'normal-assemble-exit.txt').write_text(str(x.returncode)+'\n');assert x.returncode==0
