from pathlib import Path
import sys,socket,hashlib,json
sys.path.insert(0,'/workspace/ui-shell-tools')
from owned_emulator_adb import LocalEmulator
root=Path('/workspace/ui-shell-tools/ui-candidate-preview')
def client(timeout):
 s=LocalEmulator();s.s.settimeout(timeout);s.s.setsockopt(socket.IPPROTO_TCP,socket.TCP_NODELAY,1);return s
def service(cmd,timeout=60):
 s=client(timeout)
 try:return s.read_service(cmd)
 finally:s.close()
boot=service('shell:getprop sys.boot_completed').decode().strip();print('boot:',boot,flush=True)
if boot!='1':raise RuntimeError('Boot not completed, no install attempted')
items=[]
for name in ['debug/app-debug.apk','androidTest/debug/app-debug-androidTest.apk']:
 p=root/'app/build/outputs/apk'/name;data=p.read_bytes();items.append({'path':name,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()});s=client(240)
 try:result=s.write_service('exec:cmd package install -r -S '+str(len(data)),data)
 finally:s.close()
 print(name,result.decode(),flush=True)
 if b'Success' not in result:raise RuntimeError('Install not confirmed, check state before retry')
(root/'apk-hashes.json').write_text(json.dumps(items,indent=2)+'\n')
print(service('shell:getprop ro.build.version.sdk; getprop ro.product.cpu.abi; wm size; wm density; settings get system font_scale').decode(),flush=True)
classes='com.mightyoung.muyon.product.ui.shell.ConversationShellTest,com.mightyoung.muyon.product.ui.documents.DocumentReaderPlatformTest'
r=service('shell:am instrument -w -r -e class '+classes+' com.mightyoung.muyon.uicomponentpreview.test/androidx.test.runner.AndroidJUnitRunner',600)
(root/'instrumentation.log').write_bytes(r);print(r.decode(),flush=True)
