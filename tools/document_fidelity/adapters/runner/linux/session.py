"""Concrete pinned-artifact/OS-observation verifier, configured only by trusted app."""
from dataclasses import dataclass
import math,re
from .. import model
from ..authority import ready_digest
from .backend import LinuxBackend
from .kernel import PinnedConfig

@dataclass(frozen=True)
class ScopeRecord:
    binding_digest:str
    expires_ms:float
    authorization_id:str

class LocalScopeTable:
    """Trusted application installs exact grants, never request/env JSON flags.

    This does not implement Rust authorization/CAS: app must populate only after
    live auth/revision/idempotency checks. Empty/missing table always denies.
    """
    def __init__(self,records=()):
        if any(type(r) is not ScopeRecord for r in records) or len(records)>1024:raise ValueError('trusted_scope_records')
        self.records=tuple(records)
    def authorize(self,binding,now):
        # Attempt nonce is host generated, so grants bind immutable request/
        # source/identity; per-attempt HostEvidence additionally binds its nonce.
        digest=model.digest({'request':binding.request_digest,'source':binding.source_sha256,'identity':binding.identity})
        found=[r for r in self.records if r.binding_digest==digest and type(r.expires_ms) in (int,float) and math.isfinite(r.expires_ms) and now<r.expires_ms<=now+60000 and isinstance(r.authorization_id,str) and re.fullmatch('[A-Za-z0-9_.:-]{1,128}',r.authorization_id)]
        return found[0] if len(found)==1 else None

class LinuxHostSession(model.TrustedHostSession):
    def __init__(self,backend,scope_table=None):self.backend=backend;self.scopes=scope_table;self._ready={}
    def verify_executor(self,executor):
        if executor is not self.backend or type(executor) is not LinuxBackend or not executor.native_provider() or type(self.scopes) is not LocalScopeTable:return False
        try:return bool(executor.qualify())
        except Exception:return False
    def verify_admission(self,binding,engine,policy,now_ms):
        if not self.verify_executor(self.backend):return None
        config=self.backend.config
        if config.engine!=engine or config.policy!=policy:return None
        grant=self.scopes.authorize(binding,now_ms)
        if grant is None:return None
        return model.HostEvidence(binding,engine,policy.digest(),grant.expires_ms,config.provenance.id,config.license.id,grant.authorization_id,config.isolation.id)
    def verify_ready(self,binding,ready,executor):
        if not self.verify_executor(executor):return None
        proof=executor.proof(ready.proof,'ready',binding)
        if proof is None or proof[1].ready is not ready or not executor.system.recheck_ready(proof[1].native):return None
        digest=ready_digest(ready);self._ready[binding]=digest
        return model.HostReadyEvidence(binding,digest,ready.proof.id)
    def verify_execution(self,binding,engine,proof,executor):
        item=executor.proof(proof,'terminal',binding) if executor is self.backend else None
        if item is None or binding not in self._ready or engine!=executor.config.engine:return None
        state=item[1]
        if not state.reaped or not state.released or state.snapshot is None or not item[2]['entry']:return None
        return model.HostExecutionEvidence(binding,engine,proof.id+':entry')
    def verify_terminal(self,binding,digest,receipt,candidate_sha256,proof,executor):
        item=executor.proof(proof,'terminal',binding) if executor is self.backend else None
        if item is None or self._ready.get(binding)!=digest:return None
        state,fields=item[1],item[2]
        if (not state.reaped or not state.closed or state.snapshot is None or fields['candidate']!=candidate_sha256 or fields['source']!=binding.source_sha256
                or fields['logs']!=receipt.get('log_bytes') or receipt.get('reaped') is not True or receipt.get('validation',{}).get('status')!='pass'
                or model.sha(state.snapshot.candidate)!=candidate_sha256):return None
        return model.HostTerminalEvidence(binding,digest,model.digest(receipt),candidate_sha256,proof.id)
