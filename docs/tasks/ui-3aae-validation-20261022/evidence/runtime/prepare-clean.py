from pathlib import Path
import sys,shlex
sys.path.insert(0,'/workspace/ui-shell-tools/3aae/smoke')
from device import shell,root
assert shell('getprop sys.boot_completed','boot-before-clean.txt',60).strip()=='1'
a=shell('dumpsys account','accounts-before-private.txt',120);lines=[l for l in a.splitlines() if 'Accounts:' in l];print('\n'.join(lines),flush=True);assert lines and all('Accounts: 0' in l for l in lines)
p=shell('pm path com.mightyoung.muyon.product','prior-package-path.txt',60).strip()
if p:
 assert p.startswith('package:/data/app/') and p.endswith('/base.apk')
 digest=shell('sha256sum '+shlex.quote(p.removeprefix('package:')),'prior-installed-sha256.txt',120);print(digest,flush=True)
 assert digest.split()[0]=='bf54a74d7df4d0f2f48d59be7d9608d26f813b1d20494d8e7538218b49ff6841','Unexpected app; do not clear'
 r=shell('pm uninstall com.mightyoung.muyon.product','remove-owned-c804-test-app.txt',120);print(r,flush=True);assert 'Success' in r
if shell('pm path com.mightyoung.muyon.product.test').strip():
 r=shell('pm uninstall com.mightyoung.muyon.product.test','remove-owned-probe-app.txt',120);print(r,flush=True);assert 'Success' in r
assert not shell('pm list packages com.mightyoung.muyon.product','packages-before-install.txt').strip()
print('Confirmed fresh app target; removed only the identified task-owned c804 smoke instance',flush=True)
