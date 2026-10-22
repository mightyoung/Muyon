"""Bounded inherited Unix-stream protocol. Kernel credentials, never JSON, identify peers."""
from dataclasses import dataclass
import array,json,math,os,re,select,socket,struct,time

MAX_FRAME=16384
KINDS={'hello','isolate','paused','release','entry','failure'}
class ProtocolError(ValueError):pass

def _shape(value,depth=0,budget=None):
    budget=[4096,MAX_FRAME] if budget is None else budget
    budget[0]-=1
    if budget[0]<0 or depth>24:raise ProtocolError('json_complexity')
    if type(value) is str:
        if len(value)>MAX_FRAME:raise ProtocolError('string_limit')
        budget[1]-=len(json.dumps(value).encode())
        if budget[1]<0:raise ProtocolError('encoded_budget')
        return
    if type(value) is int:
        if not -(1<<63)<=value<(1<<63):raise ProtocolError('integer_limit')
        return
    if value is None or type(value) is bool:return
    if type(value) is float and math.isfinite(value):return
    if type(value) in (list,tuple):
        for child in value:_shape(child,depth+1,budget)
    elif type(value) is dict:
        for key,child in value.items():
            if type(key) is not str or len(key)>128:raise ProtocolError('json_key')
            budget[1]-=len(json.dumps(key).encode())+3
            if budget[1]<0:raise ProtocolError('encoded_budget')
            _shape(child,depth+1,budget)
    else:raise ProtocolError('json_type')

def _pairs(pairs):
    result={}
    for key,value in pairs:
        if key in result:raise ProtocolError('duplicate_key')
        result[key]=value
    return result

def decode(payload):
    if type(payload) is not bytes or not 0<len(payload)<=MAX_FRAME:raise ProtocolError('frame_limit')
    try:value=json.loads(payload,object_pairs_hook=_pairs,parse_constant=lambda _:(_ for _ in ()).throw(ProtocolError('nonfinite')))
    except (ValueError,UnicodeError,RecursionError) as error:raise ProtocolError('invalid_json') from error
    _shape(value)
    if type(value) is not dict or set(value)!={'v','kind','attempt','request','seq','payload'}:raise ProtocolError('envelope')
    if type(value['v']) is not int or value['v']!=1 or type(value['kind']) is not str or value['kind'] not in KINDS:raise ProtocolError('version_or_kind')
    if type(value['seq']) is not int or not 0<=value['seq']<16:raise ProtocolError('sequence')
    if not isinstance(value['attempt'],str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,128}',value['attempt']):raise ProtocolError('attempt')
    if not isinstance(value['request'],str) or not re.fullmatch('[0-9a-f]{64}',value['request']):raise ProtocolError('request')
    if type(value['payload']) is not dict:raise ProtocolError('payload')
    return value

def encode(kind,attempt,request,seq,payload):
    value=dict(v=1,kind=kind,attempt=attempt,request=request,seq=seq,payload=payload)
    _shape(value)
    try:data=json.dumps(value,sort_keys=True,separators=(',',':'),allow_nan=False).encode()
    except (ValueError,TypeError,RecursionError) as error:raise ProtocolError('encoding') from error
    decode(data)
    return struct.pack('!I',len(data))+data

@dataclass(frozen=True)
class Frame:
    kind:str
    payload:dict
    seq:int
    pid:int
    uid:int
    gid:int

class Channel:
    def __init__(self,sock,attempt,request,*,expected_pid=None,expected_uid=None,max_frame=MAX_FRAME,allow_pid_zero=False):
        if sock.family!=socket.AF_UNIX or sock.type&15!=socket.SOCK_STREAM:raise ProtocolError('unix_stream_required')
        if type(max_frame) is not int or not 1<=max_frame<=MAX_FRAME:raise ProtocolError('frame_cap')
        self.socket=sock;self.attempt=attempt;self.request=request
        self.expected_pid=expected_pid;self.expected_uid=expected_uid;self.max_frame=max_frame;self.allow_pid_zero=allow_pid_zero
        self.sent=self.received=0;self._peer=None;self.closed=False
        sock.setsockopt(socket.SOL_SOCKET,socket.SO_PASSCRED,1);sock.setblocking(False)
    def close(self):self.closed=True;self.socket.close()
    def _deadline(self,timeout_ms):
        if type(timeout_ms) is not int or not 0<timeout_ms<=30000:raise ProtocolError('timeout')
        return time.monotonic()+timeout_ms/1000
    def _wait(self,deadline,write=False):
        remaining=deadline-time.monotonic()
        if remaining<=0:raise ProtocolError('ipc_timeout')
        read,writable,_=select.select([] if write else [self.socket],[self.socket] if write else [],[],remaining)
        if not (writable if write else read):raise ProtocolError('ipc_timeout')
    def _send(self,kind,payload,timeout_ms):
        data=encode(kind,self.attempt,self.request,self.sent,payload)
        if len(data)-4>self.max_frame:raise ProtocolError('frame_limit')
        deadline=self._deadline(timeout_ms);offset=0
        while offset<len(data):
            self._wait(deadline,True)
            try:count=self.socket.send(memoryview(data)[offset:])
            except (BlockingIOError,InterruptedError):continue
            if not count:raise ProtocolError('ipc_eof')
            offset+=count
        self.sent+=1
    def _read(self,count,deadline):
        result=bytearray()
        while len(result)<count:
            self._wait(deadline)
            try:data,anc,flags,_=self.socket.recvmsg(count-len(result),socket.CMSG_SPACE(12)+socket.CMSG_SPACE(64))
            except (BlockingIOError,InterruptedError):continue
            credentials=[];unexpected=False
            for level,kind,payload in anc:
                if level==socket.SOL_SOCKET and kind==socket.SCM_CREDENTIALS and len(payload)==12:credentials.append(struct.unpack('3i',payload))
                else:
                    unexpected=True
                    if level==socket.SOL_SOCKET and kind==socket.SCM_RIGHTS:
                        fds=array.array('i');fds.frombytes(payload[:len(payload)//fds.itemsize*fds.itemsize])
                        for fd in fds:os.close(fd)
            if flags&(socket.MSG_CTRUNC|socket.MSG_TRUNC) or unexpected:raise ProtocolError('ancillary_data')
            if not data:raise ProtocolError('ipc_eof')
            if len(credentials)!=1:raise ProtocolError('credentials_missing')
            peer=credentials[0]
            if ((self._peer is not None and self._peer!=peer) or (self.expected_pid is not None and peer[0]!=self.expected_pid)
                    or (self.expected_uid is not None and peer[1]!=self.expected_uid) or peer[0]<0 or (peer[0]==0 and not self.allow_pid_zero)):raise ProtocolError('peer_mismatch')
            self._peer=peer;result.extend(data)
        return bytes(result)
    def _receive(self,timeout_ms):
        deadline=self._deadline(timeout_ms);length=struct.unpack('!I',self._read(4,deadline))[0]
        if not 0<length<=self.max_frame:raise ProtocolError('frame_limit')
        value=decode(self._read(length,deadline))
        if value['attempt']!=self.attempt or value['request']!=self.request or value['seq']!=self.received:raise ProtocolError('binding_or_replay')
        self.received+=1
        return Frame(value['kind'],value['payload'],value['seq'],*self._peer)

    def send(self,kind,payload,timeout_ms):
        if self.closed:raise ProtocolError('channel_closed')
        try:return self._send(kind,payload,timeout_ms)
        except Exception as error:
            self.close()
            if isinstance(error,ProtocolError):raise
            raise ProtocolError('ipc_send_failed') from error
    def receive(self,timeout_ms):
        if self.closed:raise ProtocolError('channel_closed')
        try:return self._receive(timeout_ms)
        except Exception as error:
            self.close()
            if isinstance(error,ProtocolError):raise
            raise ProtocolError('ipc_receive_failed') from error
