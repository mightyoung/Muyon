from pathlib import Path
import sys,json,hashlib
sys.path.insert(0,'/workspace/ui-shell-tools/product-smoke')
from device import root,client,shell
m=json.loads(Path('/workspace/ui-shell-tools/candidate-deliverables.json').read_text());p=Path(m['apk']['path']);data=p.read_bytes();assert len(data)==426369208 and hashlib.sha256(data).hexdigest()==m['apk']['sha256']
assert shell('getprop sys.boot_completed').strip()=='1'
assert shell('pm list packages com.mightyoung.muyon.product').strip()==''
assert 'Accounts: 0' in (root/'accounts-before-private.txt').read_text()
s=client(300)
try:r=s.write_service('exec:cmd package install -S '+str(len(data)),data)
finally:s.close()
(root/'install.log').write_bytes(r);print(r.decode(),flush=True)
if b'Success' not in r:raise RuntimeError('Installation unconfirmed; inspect package before retry')
print(shell('dumpsys package com.mightyoung.muyon.product','installed-package.txt'),flush=True)
print(shell('am start -W -n com.mightyoung.muyon.product/.MainActivity','cold-start.txt',120),flush=True)
