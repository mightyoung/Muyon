from pathlib import Path
import sys,hashlib
sys.path.insert(0,'/workspace/ui-shell-tools/3aae/smoke')
from device import client,service,shell,root
p=root/'read-only-probe-androidTest.apk';data=p.read_bytes();s=client(120)
try:r=s.write_service('exec:cmd package install -r -S '+str(len(data)),data)
finally:s.close()
(root/'probe-install.log').write_bytes(r);print(r.decode(),flush=True)
assert b'Success' in r
r=service('shell:am instrument -w -r -e class com.mightyoung.muyon.product.ui.shell.ConversationShellTest,com.mightyoung.muyon.product.ui.documents.DocumentReaderPlatformTest,com.mightyoung.muyon.product.ui.shell.RuntimeHealthSmokeProbe,com.mightyoung.muyon.product.agentipc.BotNativeServiceAcceptanceTest com.mightyoung.muyon.product.test/androidx.test.runner.AndroidJUnitRunner',600)
(root/'probe-instrumentation.log').write_bytes(r);print(r.decode(),flush=True)
print(shell('logcat -d -s MuyonColdSmoke BotNativeAcceptance','runtime-health.log',120),flush=True)
print(shell("run-as com.mightyoung.muyon.product ls -la files/muyon-product-v2",'private-test-files.txt',60),flush=True)
print(shell('getprop ro.build.version.sdk; getprop ro.product.cpu.abi; wm size; wm density; settings get system font_scale; cmd uimode night','environment.txt',60),flush=True)
