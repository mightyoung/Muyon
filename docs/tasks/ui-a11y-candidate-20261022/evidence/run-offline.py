import os,subprocess,json
from pathlib import Path
repo=Path('/workspace/muyon-ui-candidate');out=Path('/workspace/ui-shell-tools/candidate-offline');out.mkdir(exist_ok=True)
env=dict(os.environ,JAVA_HOME='/workspace/ui-shell-tools/jdk-17.0.21+9',KOTLINC='/workspace/ui-shell-tools/kotlin-2.2.20/kotlinc/bin/kotlinc',JSON_JAR='/workspace/ui-shell-tools/android-json-0.0.20131108.vaadin1.jar',PYTHONDONTWRITEBYTECODE='1')
env['PATH']=env['JAVA_HOME']+'/bin:'+env['PATH']
commands={
 'snapshot':['bash','apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/shell/run-snapshot-checks.sh'],
 'host-shell':['bash','apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/shell/run-host-shell-checks.sh'],
 'reader':['bash','apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/documents/run-offline.sh'],
 'cards':['bash','apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/cards/run-offline.sh'],
 'configuration':['bash','apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/configuration/run-offline-checks.sh'],
 'bot':['bash','apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/agents/setup/run-offline-checks.sh'],
 'contrast':['python3','-m','unittest','discover','-s','apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/ui/system/checks','-v'],
 'package-checks':['python3','-m','unittest','discover','-s','apps/muyon_android/checks','-v']}
results=[]
for name,cmd in commands.items():
 with (out/(name+'.log')).open('w') as f:r=subprocess.run(cmd,cwd=repo,env=env,stdout=f,stderr=subprocess.STDOUT)
 results.append({'name':name,'command':cmd,'exit_code':r.returncode});print(name,r.returncode,flush=True)
(out/'results.json').write_text(json.dumps(results,indent=2)+'\n')
