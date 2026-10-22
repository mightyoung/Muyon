from pathlib import Path
import sys,time
sys.path.insert(0,'/workspace/ui-shell-tools')
from owned_emulator_adb import LocalEmulator
root=Path('/workspace/ui-shell-tools/ui-component-preview')
def service(cmd,timeout=60):
 s=LocalEmulator();s.s.settimeout(timeout)
 try:return s.read_service(cmd)
 finally:s.close()
print('boot:',service('shell:getprop sys.boot_completed').decode(),flush=True)
for name in ['debug/app-debug.apk','androidTest/debug/app-debug-androidTest.apk']:
 p=root/'app/build/outputs/apk'/name; data=p.read_bytes();s=LocalEmulator();s.s.settimeout(240)
 try:result=s.write_service('exec:cmd package install -r -S '+str(len(data)),data)
 finally:s.close()
 print(name,result.decode(),flush=True)
 if b'Success' not in result:raise RuntimeError('Install not confirmed; do not retry without checking package status')
print(service('shell:getprop ro.build.version.sdk; getprop ro.product.cpu.abi; wm size; wm density; settings get system font_scale').decode(),flush=True)
result=service('shell:am instrument -w -r -e class com.mightyoung.muyon.product.ui.documents.DocumentReaderPlatformTest com.mightyoung.muyon.uicomponentpreview.test/androidx.test.runner.AndroidJUnitRunner',600)
Path('/workspace/ui-shell-tools/reader-device-instrumentation.log').write_bytes(result)
print(result.decode(),flush=True)
