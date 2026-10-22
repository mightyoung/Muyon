"""One-use child-local permit from inherited authenticated broker FD only."""
from dataclasses import asdict
import math,os,time
from .. import model
from ...protocol import parse_request,IDENTITY_FIELDS
from .ipc import Channel

_SEAL=object()
class RemoteWorkerPermit:
    __slots__=('request','engine','policy','binding','expiry','channel','used','entered')
    def __init__(self,seal,request,grant,channel):
        if seal is not _SEAL or type(channel) is not Channel:raise TypeError('broker_fd_required')
        if type(grant) is not dict or set(grant)!={'engine','policy','binding','expires_ms'}:raise ValueError('grant_shape')
        self.request=parse_request(request);self.engine=model.EngineIdentity(**grant['engine']);self.policy=model.Policy(**grant['policy'])
        b=grant['binding'];self.binding=model.Binding(b['attempt_id'],b['request_digest'],b['source_sha256'],tuple(b['identity']))
        if set(b)!={'attempt_id','request_digest','source_sha256','identity'} or self.binding.request_digest!=model.digest(self.request) or self.binding.source_sha256!=self.request['source_sha256'] or self.binding.identity!=tuple(self.request[k] for k in IDENTITY_FIELDS) or self.binding.attempt_id!=channel.attempt or self.binding.request_digest!=channel.request:raise ValueError('grant_binding')
        self.expiry=grant['expires_ms']
        if type(self.expiry) not in (int,float) or not math.isfinite(self.expiry) or not time.monotonic()*1000<self.expiry<=time.monotonic()*1000+60000:raise ValueError('grant_expiry')
        self.channel=channel;self.used=self.entered=False
    def __reduce__(self):raise TypeError('worker_permit_not_serializable')
    def consume(self,request,source,candidate,engine_id):
        fmt={'openpyxl':'xlsx','python-docx':'docx','python-pptx':'pptx'}.get(engine_id)
        if self.used or self.request!=parse_request(request) or self.engine.engine_id!=engine_id or time.monotonic()*1000>=self.expiry or os.fspath(source)!='/input/source.'+str(fmt) or os.fspath(candidate)!='/output/candidate.'+str(fmt):raise ValueError('worker_grant_invalid')
        self.used=True;return self.engine,self.policy,self.binding
    def engine_entered(self):
        if not self.used or self.entered or time.monotonic()*1000>=self.expiry:raise ValueError('entry_state')
        self.entered=True
        try:self.channel.send('entry',{'engine':self.engine.engine_id,'version':self.engine.version},1000)
        finally:self.channel.close()

def receive_permit(channel,request):
    # Channel comes only from fixed inherited FD bootstrap; envelope is data.
    # This is not exported as a model tool or a JSON bootstrap installer.
    if type(channel) is not Channel:raise TypeError('inherited_channel_required')
    frame=channel.receive(1000)
    if frame.kind!='release':raise ValueError('worker_not_released')
    return RemoteWorkerPermit(_SEAL,request,frame.payload,channel)
