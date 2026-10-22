"""Socketpair + pure/fake syscall tests; never sandbox/process/engine starts."""
import json,os,socket,struct,threading,time,unittest
from tools.document_fidelity.adapters.runner.linux import ipc,snapshot

class IPCTests(unittest.TestCase):
    def pair(self,**kwargs):
        a,b=socket.socketpair(socket.AF_UNIX,socket.SOCK_STREAM)
        self.addCleanup(a.close);self.addCleanup(b.close)
        return ipc.Channel(a,'attempt_1','a'*64,expected_pid=os.getpid(),expected_uid=os.getuid(),**kwargs),ipc.Channel(b,'attempt_1','a'*64,expected_pid=os.getpid(),expected_uid=os.getuid(),**kwargs)
    def test_real_socketpair_credentials_sequence_binding_and_eof(self):
        a,b=self.pair();a.send('paused',{'phase':'waiting'},100)
        frame=b.receive(100);self.assertEqual(os.getpid(),frame.pid);self.assertEqual('paused',frame.kind)
        a.send('entry',{},100);self.assertEqual(1,b.receive(100).seq)
        a.close()
        with self.assertRaises(ipc.ProtocolError):b.receive(100)
    def test_partial_io_and_replay_wrong_binding_timeout(self):
        a,b=self.pair(max_frame=2048)
        raw=ipc.encode('paused','attempt_1','a'*64,0,{})
        for chunk in (raw[:2],raw[2:7],raw[7:]):a.socket.sendall(chunk)
        self.assertEqual('paused',b.receive(100).kind)
        a.socket.sendall(raw)
        with self.assertRaises(ipc.ProtocolError):b.receive(100)
        a,b=self.pair();a.socket.sendall(ipc.encode('paused','wrong','a'*64,0,{}))
        with self.assertRaises(ipc.ProtocolError):b.receive(100)
        a,b=self.pair()
        with self.assertRaises(ipc.ProtocolError):b.receive(5)
    def test_limit_duplicate_json_wrong_peer_and_truncation(self):
        a,b=self.pair(max_frame=32);a.socket.sendall(struct.pack('!I',33))
        with self.assertRaises(ipc.ProtocolError):b.receive(100)
        a,b=self.pair();a.socket.sendall(struct.pack('!I',5)+b'{');a.close()
        with self.assertRaises(ipc.ProtocolError):b.receive(100)
        a,b=self.pair();b.expected_pid=os.getpid()+1;a.send('paused',{},100)
        with self.assertRaises(ipc.ProtocolError):b.receive(100)
        for payload in (b'{"v":1,"v":1}',b'{"x":NaN}'):
            with self.assertRaises(ipc.ProtocolError):ipc.decode(payload)
    def test_send_is_bounded_and_unknown_fields_refused(self):
        a,b=self.pair(max_frame=64)
        with self.assertRaises(ipc.ProtocolError):a.send('paused',{'large':'x'*1000},10)
        with self.assertRaises(ipc.ProtocolError):ipc.encode('wrong','attempt_1','a'*64,0,{})
        with self.assertRaises(ipc.ProtocolError):ipc.encode('paused','attempt_1','a'*64,True,{})

class FakeFiles:
    def __init__(self,mode='ok'):self.mode=mode;self.calls=[];self.reads=0
    def names(self,dirfd):return ['candidate.xlsx','side'] if self.mode=='extra' else ['candidate.xlsx']
    def open_read(self,dirfd,name):self.calls.append(('open',dirfd,name));return 12
    def info(self,fd):
        self.reads+=1
        return snapshot.FileInfo(1,2,0o100600,2 if self.mode=='linked' else 1,3,4 if self.mode!='changed' or self.reads==1 else 5,6)
    def read(self,fd,count):return b'abc' if not hasattr(self,'read_done') else b''
    def close(self,fd):self.calls.append(('close',fd))

class SnapshotTests(unittest.TestCase):
    def test_reaped_required_before_open_and_stable_regular_bytes(self):
        fs=FakeFiles()
        with self.assertRaises(ValueError):snapshot.capture(fs,8,'candidate.xlsx',10,reaped=False)
        self.assertFalse(fs.calls)
        # Fake read is stateful and bounded, no filesystem access.
        chunks=iter([b'ab',b'c',b'']);fs.read=lambda fd,n:next(chunks)
        self.assertEqual(b'abc',snapshot.capture(fs,8,'candidate.xlsx',10,reaped=True))
        self.assertIn(('close',12),fs.calls)
    def test_changed_links_extras_and_path_escape_refused(self):
        for mode in ('linked','changed','extra'):
            fs=FakeFiles(mode);chunks=iter([b'abc',b'']);fs.read=lambda fd,n:next(chunks)
            with self.assertRaises(ValueError):snapshot.capture(fs,8,'candidate.xlsx',10,reaped=True)
        for name in ('../candidate','/tmp/x','a/b','.'):
            with self.assertRaises(ValueError):snapshot.capture(FakeFiles(),8,name,10,reaped=True)
