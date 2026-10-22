from pathlib import Path
import sys,json,hashlib
sys.path.insert(0,'/workspace/ui-shell-tools/post102/smoke')
from device import root,client,shell
m=json.loads(Path('/workspace/ui-shell-tools/post102/artifacts.json').read_text());a=m['artifacts'][0];p=Path(a['path']);data=p.read_bytes();assert len(data)==a['size_bytes'] and hashlib.sha256(data).hexdigest()==a['sha256'];assert a['sha256']=='bf54a74d7df4d0f2f48d59be7d9608d26f813b1d20494d8e7538218b49ff6841'
assert shell('getprop sys.boot_completed').strip()=='1';assert not shell('pm list packages com.mightyoung.muyon.product').strip()
s=client(300)
try:r=s.write_service('exec:cmd package install -S '+str(len(data)),data)
finally:s.close()
(root/'install.log').write_bytes(r);print(r.decode(),flush=True)
if b'Success' not in r:raise RuntimeError('Install unconfirmed; inspect state before retry')
print(shell('dumpsys package com.mightyoung.muyon.product','installed-package.txt'),flush=True)
print(shell('am start -W -n com.mightyoung.muyon.product/.MainActivity','cold-start.txt',120),flush=True)
