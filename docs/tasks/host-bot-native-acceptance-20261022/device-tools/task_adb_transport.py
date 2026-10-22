"""Task-local standard ADB transport for ONLY our disposable API26 emulator.
No host daemon, home writes, key generation, AUTH handling or security changes.
AUTH/unknown handshake is a hard stop. No mutating command is automatically retried.
This is platform transport, not a ProductService/native substitute.
"""
import socket, struct, time, json, re
from pathlib import Path

class Transport:
    def __init__(self):
        self.s=socket.create_connection(('127.0.0.1',5581),timeout=15)
        self.s.settimeout(300)
        self.pending=bytearray();self.remote=0;self.closed=False
        self.send(b'CNXN',0x01000000,4096,b'host::\0')
        c,a,b,p=self.packet()
        if c!=b'CNXN':
            self.s.close()
            raise RuntimeError('AUTH_OR_UNEXPECTED_HANDSHAKE_STOP: '+repr(c))
        self.max_payload=min(b,4096)
        self.banner=p.decode('utf8','replace')
    def exact(self,n):
        out=bytearray()
        while len(out)<n:
            x=self.s.recv(n-len(out))
            if not x:raise EOFError('transport closed; outcome uncertain, no retry')
            out.extend(x)
        return bytes(out)
    def packet(self):
        c,a,b,n,checksum,magic=struct.unpack('<6I',self.exact(24))
        if c^magic!=0xffffffff or n>1048576:raise RuntimeError('invalid packet')
        data=self.exact(n)
        if sum(data)&0xffffffff!=checksum:raise RuntimeError('invalid checksum')
        return c.to_bytes(4,'little'),a,b,data
    def send(self,c,a,b,p=b''):
        value=int.from_bytes(c,'little')
        self.s.sendall(struct.pack('<6I',value,a,b,len(p),sum(p)&0xffffffff,value^0xffffffff)+p)
    def event(self):
        c,a,b,p=self.packet()
        if c not in (b'WRTE',b'OKAY',b'CLSE'):raise RuntimeError('AUTH_OR_UNKNOWN_STOP: '+repr(c))
        if b!=1 or a!=self.remote:raise RuntimeError('foreign stream')
        if c==b'WRTE':
            self.pending.extend(p);self.send(b'OKAY',1,self.remote)
        elif c==b'CLSE':
            self.closed=True;self.send(b'CLSE',1,self.remote)
        return c,a,b,p
    def open(self,service):
        self.send(b'OPEN',1,0,service.encode()+b'\0')
        c,a,b,p=self.packet()
        if c!=b'OKAY' or b!=1 or a==0:raise RuntimeError('service refused: '+repr((c,p)))
        self.remote=a
    def write(self,data):
        for i in range(0,len(data),self.max_payload):
            self.send(b'WRTE',1,self.remote,data[i:i+self.max_payload])
            while True:
                c,a,b,p=self.event()
                if c==b'OKAY':break
                if self.closed:raise EOFError('closed during write; do not replay')
    def read(self,n):
        while len(self.pending)<n:
            if self.closed:raise EOFError('short stream')
            self.event()
        out=bytes(self.pending[:n]);del self.pending[:n];return out
    def close(self):self.s.close()

def shell(command,output_path=None):
    t=Transport();output=Path(output_path).open('wb') if output_path else None;written=0
    try:
        t.open('shell:'+command)
        while not t.closed:
            t.event()
            if output:
                output.write(t.pending[written:]);output.flush();written=len(t.pending)
        return bytes(t.pending).decode('utf8','replace')
    finally:
        if output:output.close()
        t.close()

def push(source,destination):
    if not re.fullmatch(r'/data/local/tmp/muyon-bot-[a-z0-9-]+\.apk', destination):
        raise ValueError('task-owned APK staging path only')
    t=Transport()
    try:
        t.open('sync:')
        name=(destination+',33188').encode()
        t.write(b'SEND'+struct.pack('<I',len(name))+name)
        with Path(source).open('rb') as f:
            while True:
                chunk=f.read(65536)
                if not chunk:break
                t.write(b'DATA'+struct.pack('<I',len(chunk))+chunk)
        t.write(b'DONE'+struct.pack('<I',int(time.time())))
        kind=t.read(4);length=struct.unpack('<I',t.read(4))[0]
        if kind!=b'OKAY':raise RuntimeError('sync refused: '+repr(t.read(length)))
        t.send(b'CLSE',1,t.remote)
        return {'bytes':Path(source).stat().st_size,'destination':destination,'sync':'OKAY'}
    finally:t.close()

if __name__=='__main__':
    import sys
    if sys.argv[1]=='readiness':
        print(shell('getprop sys.boot_completed'))
        print(shell('getprop ro.build.version.sdk'))
        print(shell('getprop ro.product.cpu.abi'))
        print(shell('pm path com.mightyoung.muyon.product'))
    else:raise SystemExit('No automatic mutation entrypoint; reviewed task calls only')
