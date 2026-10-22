from pathlib import Path
import sys,socket,time,json
sys.path.insert(0,'/workspace/ui-shell-tools')
from owned_emulator_adb import LocalEmulator
root=Path('/workspace/ui-shell-tools/post102/smoke')
def client(timeout=90):
 s=LocalEmulator();s.s.settimeout(timeout);s.s.setsockopt(socket.IPPROTO_TCP,socket.TCP_NODELAY,1);return s
def service(cmd,timeout=90):
 s=client(timeout)
 try:return s.read_service(cmd)
 finally:s.close()
def shell(cmd,name=None,timeout=90):
 r=service('shell:'+cmd,timeout)
 if name:(root/name).write_bytes(r)
 return r.decode(errors='replace')
if __name__=='__main__':
 for cmd,name in [('getprop sys.boot_completed','boot.txt'),('pm list packages com.mightyoung.muyon.product','packages-before.txt'),('dumpsys account','accounts-before-private.txt')]:
  print('CHECK',name,flush=True)
  r=shell(cmd,name,120)
  if name=='accounts-before-private.txt':
   lines=[s for s in r.splitlines() if 'Accounts:' in s];print('\n'.join(lines),flush=True)
  else:print(r,flush=True)
