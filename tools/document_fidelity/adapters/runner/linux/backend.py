"""Concrete Linux backend. No configured provider => HOLD before process creation."""
from dataclasses import dataclass
from .. import model
from .kernel import NativeLinuxSystem,PinnedConfig

class Hold(ValueError):pass
_SEAL=object()
class NativeProof:
    __slots__=('id',)
    def __init__(self,seal,id):
        if seal is not _SEAL:raise TypeError('broker_observation_required')
        self.id=id
    def __reduce__(self):raise TypeError('native_proof_not_serializable')
@dataclass
class Attempt:
    id:str
    spec:dict
    source:bytes
    job:bytes
    native:object=None
    launch_attempted:bool=False
    ready:object=None
    binding:object=None
    snapshot:object=None
    released:bool=False
    reaped:bool=False
    closed:bool=False

class LinuxBackend(model.HostOSBackend):
    def __init__(self,config=None,system=None):
        self.config=config;self.system=NativeLinuxSystem() if system is None else system
        self.attempt=None;self._proofs={};self.qualification=None
    def native_provider(self):return type(self.system) is NativeLinuxSystem and type(self.config) is PinnedConfig
    def qualify(self):
        if self.config is None:raise Hold('linux_provider_unconfigured')
        if self.qualification is None:self.qualification=self.system.qualify(self.config)
        return self.qualification
    def now_ms(self):return self.system.now_ms()
    def _state(self,state):
        if state is not self.attempt or state is None or state.native is None:raise Hold('attempt_ownership_mismatch')
        return state
    def reserve(self,attempt,spec,source,job):
        if self.attempt is not None:raise Hold('single_attempt_backend_no_retry')
        self.qualify()
        state=Attempt(attempt,spec,source,job);self.attempt=state
        def register(native):
            if native is None or state.native is not None:raise Hold('staging_record_registration')
            state.native=native
        staged=self.system.stage(attempt,spec,source,job,register)
        if staged is not state.native:raise Hold('staging_record_mismatch')
        # Record ownership BEFORE launch; reconciliation must inspect even if
        # logical spawn never happened or launch throws after creating a child.
        state.launch_attempted=True
        self.system.launch(state.native)
        return state
    def _proof(self,kind,state,**fields):
        if not self.native_provider():return None
        proof=NativeProof(_SEAL,kind+':'+model.digest({'attempt':state.id,'n':len(self._proofs),'fields':fields}))
        self._proofs[proof]=(kind,state,fields)
        return proof
    def proof(self,value,kind,binding):
        item=self._proofs.get(value) if type(value) is NativeProof else None
        if not self.native_provider() or not item or item[0]!=kind or item[1].binding!=binding:return None
        return item
    def ready(self,workspace,binding,engine,policy):
        state=self._state(workspace);state.binding=binding
        observed=self.system.observe_ready(state.native,binding,engine,policy)
        proof=self._proof('ready',state,observed=observed)
        state.ready=model.SandboxReady(binding,engine,policy.digest(),True,True,True,True,True,True,proof)
        return state.ready
    def spawn(self,workspace,spec,lease):
        state=self._state(workspace)
        if state.closed or state.reaped or state.released or state.ready is None or state.spec!=spec:raise Hold('release_stage_invalid')
        authority=lease._issuer
        import json
        raw=json.loads(state.job)
        def release(engine,policy,binding,expires_ms):
            grant=dict(expires_ms=expires_ms,engine=__import__('dataclasses').asdict(engine),policy=__import__('dataclasses').asdict(policy),binding=__import__('dataclasses').asdict(binding))
            # This callback executes under the ORIGINAL Authority lock. No
            # serialized capability or independently manufactured issuer exists.
            self.system.release(state.native,grant)
        if not authority.dispatch_worker(lease,raw,self,self.now_ms(),spec['format'],release):raise Hold('worker_phase_not_authorized')
        state.released=True
        return state
    def reconcile(self,attempt):
        state=self.attempt
        if state is None:return model.Reconciliation(True,None,None)
        if state.id!=attempt:return model.Reconciliation(False,None,None)
        if state.native is None:return model.Reconciliation(True,None,None)
        if getattr(state.native,'cleanup_failed',False):return model.Reconciliation(False,state,None)
        if getattr(state.native,'stage_discarded',False):return model.Reconciliation(True,None,None)
        if getattr(state.native,'staging_failed',False):return model.Reconciliation(False,state,None)
        if state.launch_attempted and self.native_provider() and not self.system.reconcile(state.native):return model.Reconciliation(False,state,None)
        return model.Reconciliation(True,state,state if state.launch_attempted else None)
    def poll(self,process,wait_ms):return self.system.poll(self._state(process).native,wait_ms)
    def measure(self,workspace):return self.system.measure(self._state(workspace).native)
    def terminate_tree(self,process):self.system.terminate(self._state(process).native)
    def kill_tree(self,process):self.system.kill(self._state(process).native)
    def reap_tree(self,process,wait_ms):
        state=self._state(process)
        result=self.system.reap(state.native,wait_ms)
        state.reaped=result is True
        return state.reaped
    def snapshot(self,workspace,policy):
        state=self._state(workspace)
        if not state.reaped or state.closed:raise Hold('snapshot_before_reap')
        state.snapshot=self.system.capture(state.native,policy)
        return state.snapshot
    def terminal_proof(self,process,workspace):
        state=self._state(process)
        if state is not workspace or not state.reaped or state.snapshot is None or not state.released:raise Hold('terminal_state_invalid')
        if not getattr(state.native,'entry',None):return None
        return self._proof('terminal',state,candidate=model.sha(state.snapshot.candidate),source=model.sha(state.snapshot.source),job=model.sha(state.snapshot.job),entry=state.native.entry,logs=state.native.log_bytes.copy())
    def cleanup(self,workspace):
        state=self._state(workspace)
        if not state.reaped:raise Hold('cleanup_before_reap')
        self.system.cleanup(state.native);state.closed=True
    def quarantine(self,attempt,workspace=None):
        state=self.attempt
        if state is not None and state.id==attempt and state.native is not None:self.system.quarantine(state.native)
