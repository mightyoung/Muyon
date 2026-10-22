"""Normal ADB transport for the task-owned local emulator; no AUTH bypass or host config writes.
Accepts only the existing guest's CNXN greeting; AUTH is a hard stop.
"""
import socket, struct
class LocalEmulator:
 def __init__(self):
  self.s=socket.create_connection(('127.0.0.1',5559),timeout=20)
  self.send(b'CNXN',0x01000000,4096,b'host::\0')
  c,a,b,p=self.recv()
  if c!=b'CNXN':
   self.s.close();raise PermissionError('Guest did not accept normal CNXN; no authentication changes attempted')
 def send(self,c,a,b,p=b''):
  n=int.from_bytes(c,'little');self.s.sendall(struct.pack('<6I',n,a,b,len(p),sum(p)&0xffffffff,n^0xffffffff)+p)
 def exact(self,n):
  p=b''
  while len(p)<n:
   q=self.s.recv(n-len(p))
   if not q:raise EOFError('guest closed transport')
   p+=q
  return p
 def recv(self):
  n,a,b,k,checksum,magic=struct.unpack('<6I',self.exact(24))
  if magic!=(n^0xffffffff) or k>16*1024*1024:raise ValueError('invalid guest framing')
  return n.to_bytes(4,'little'),a,b,self.exact(k)
 def read_service(self,service):
  self.send(b'OPEN',1,0,service.encode()+b'\0');out=bytearray()
  while True:
   c,a,b,p=self.recv()
   if c==b'WRTE':
    out.extend(p)
    if len(out)>32*1024*1024:raise ValueError('bounded output exceeded')
    self.send(b'OKAY',1,a)
   elif c==b'CLSE':
    self.send(b'CLSE',1,a);return bytes(out)
   elif c!=b'OKAY':raise ValueError('unexpected ADB command')
 def write_service(self,service,data):
  self.send(b'OPEN',1,0,service.encode()+b'\0');out=bytearray();remote=None
  while remote is None:
   c,a,b,p=self.recv()
   if c==b'OKAY':remote=a
   elif c==b'CLSE':return p
   elif c==b'WRTE':out.extend(p);self.send(b'OKAY',1,a)
   else:raise ValueError('unexpected ADB handshake')
  for start in range(0,len(data),4096):
   self.send(b'WRTE',1,remote,data[start:start+4096])
   while True:
    c,a,b,p=self.recv()
    if c==b'OKAY':break
    if c==b'WRTE':out.extend(p);self.send(b'OKAY',1,a)
    elif c==b'CLSE':self.send(b'CLSE',1,a);return bytes(out)
    else:raise ValueError('unexpected ADB write response')
  while True:
   c,a,b,p=self.recv()
   if c==b'WRTE':out.extend(p);self.send(b'OKAY',1,a)
   elif c==b'CLSE':self.send(b'CLSE',1,a);return bytes(out)
   elif c!=b'OKAY':raise ValueError('unexpected ADB completion')
 def close(self):self.s.close()
if __name__=='__main__':
 d=LocalEmulator()
 try:print(d.read_service('shell:getprop sys.boot_completed; getprop ro.build.version.sdk; wm size; wm density; settings get system font_scale').decode())
 finally:d.close()
