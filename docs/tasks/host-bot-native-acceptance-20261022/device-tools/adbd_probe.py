"""Read-only standard ADB CNXN capability probe to this task's emulator only."""
import socket, struct, json
from pathlib import Path
out={'endpoint':'127.0.0.1:5581','security_changed':False,'credentials_used':False}
try:
 with socket.create_connection(('127.0.0.1',5581),timeout=10) as s:
  payload=b'host::\x00';cmd=int.from_bytes(b'CNXN','little')
  s.sendall(struct.pack('<6I',cmd,0x01000000,4096,len(payload),sum(payload),cmd^0xffffffff)+payload)
  def read(n):
   b=b''
   while len(b)<n:
    x=s.recv(n-len(b))
    if not x:raise RuntimeError('closed before handshake reply')
    b+=x
   return b
  h=struct.unpack('<6I',read(24))
  if h[3]>1048576:raise RuntimeError('invalid bounded reply')
  body=read(h[3]);name=h[0].to_bytes(4,'little').decode('ascii')
  out.update(command=name,arg0=h[1],arg1=h[2])
  if name=='CNXN':out['body']=body.decode('utf8','replace')
  elif name=='AUTH':out['status']='AUTH_REQUIRED_STOP_NO_KEY_OR_RETRY'
  else:out['status']='UNEXPECTED_STOP'
except Exception as e:out.update(status='UNCONFIRMED_CLOSED',error=repr(e))
Path('/workspace/host-bot-native-tools/evidence/adbd-readonly-probe.json').write_text(json.dumps(out,indent=2))
print(json.dumps(out))
