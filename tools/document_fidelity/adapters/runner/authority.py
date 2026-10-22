"""Process-local capabilities issued only through trusted host bootstrap.

No JSON/pickle token factory. Simulation and production records never interchange.
"""
import math
import re
import threading
from dataclasses import asdict
from . import model
from ..protocol import parse_request,IDENTITY_FIELDS

_SEAL=object()
# Fail closed at capacity; never evict replay history to silently reopen an attempt.
MAX_ATTEMPTS=1024


class Capability:
    __slots__=('_issuer',)
    def __new__(cls,seal=None,issuer=None):
        if seal is not _SEAL:raise TypeError('opaque_capability')
        return super().__new__(cls)
    def __init__(self,seal=None,issuer=None):self._issuer=issuer
    def __reduce__(self):raise TypeError('capability_not_serializable')


def valid_proof_id(value):
    return isinstance(value,str) and re.fullmatch(r'[A-Za-z0-9_.:-]{1,128}',value) is not None


def bind(raw,attempt):
    request=parse_request(raw)
    return model.Binding(attempt,model.digest(request),request['source_sha256'],tuple(request[k] for k in IDENTITY_FIELDS))


def ready_digest(ready):
    return model.digest(dict(binding=asdict(ready.binding),engine=asdict(ready.engine),policy_digest=ready.policy_digest,
                             guards=[ready.source_read_only,ready.job_read_only,ready.no_network,ready.private_output,ready.sanitized_environment,ready.limits_enforced]))


class Authority:
    def __init__(self,engine,policy,session=None):
        if type(engine) is not model.EngineIdentity or type(policy) is not model.Policy:raise TypeError('invalid_host_configuration')
        if session is not None and not isinstance(session,model.TrustedHostSession):raise TypeError('trusted_bootstrap_session_required')
        self.engine,self.policy,self.session=engine,policy,session
        self.assurance='host_verified' if session is not None else 'simulation'
        self._records={};self._attempts=set();self._lock=threading.RLock()
    @classmethod
    def simulation(cls,engine,policy):return cls(engine,policy)
    @classmethod
    def host(cls,engine,policy,session):
        if not isinstance(session,model.TrustedHostSession):raise TypeError('trusted_bootstrap_session_required')
        return cls(engine,policy,session)
    def admit(self,raw,source_sha256,executor,attempt,now):
        with self._lock:
            request=parse_request(raw)
            if source_sha256!=request['source_sha256'] or not isinstance(attempt,str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,128}',attempt):return None
            if not isinstance(now,(int,float)) or isinstance(now,bool) or not math.isfinite(now) or now<0:return None
            if attempt in self._attempts or len(self._attempts)>=MAX_ATTEMPTS:return None
            if self.assurance=='simulation':
                if getattr(executor,'assurance',None)!='simulation':return None
                expiry=now+self.policy.timeout_ms+3*self.policy.grace_ms+1000
            else:
                if not isinstance(executor,model.HostOSBackend) or self.session.verify_executor(executor) is not True:return None
                context=bind(request,attempt)
                evidence=self.session.verify_admission(context,self.engine,self.policy,now)
                if type(evidence) is not model.HostEvidence or evidence.binding!=context or evidence.engine!=self.engine or evidence.policy_digest!=self.policy.digest():return None
                expiry=evidence.expires_ms
                if type(expiry) not in (int,float) or not math.isfinite(expiry) or not now<expiry<=now+60000:return None
                refs=(evidence.provenance_review_id,evidence.license_review_id,evidence.scope_review_id,evidence.isolation_attestation_id)
                if any(not isinstance(r,str) or not re.fullmatch(r'[A-Za-z0-9_.:-]{1,128}',r) for r in refs):return None
            cap=Capability(_SEAL,self)
            self._records[cap]=dict(kind='lease',binding=bind(request,attempt),executor=executor,expiry=expiry,claimed=False,ready=None)
            self._attempts.add(attempt)
            return cap
    def _record(self,cap):
        return self._records.get(cap) if type(cap) is Capability else None
    def check_lease(self,cap,raw,executor,now):
        with self._lock:
            record=self._record(cap)
            try:return bool(record and record['kind']=='lease' and not record.get('closed') and record['executor'] is executor and record['binding']==bind(raw,record['binding'].attempt_id) and type(now) in (int,float) and math.isfinite(now) and 0<=now<record['expiry'])
            except (ValueError,TypeError,KeyError):return False
    def claim(self,cap,raw,executor,now):
        with self._lock:
            if not self.check_lease(cap,raw,executor,now):return False
            record=self._record(cap)
            if record['claimed']:return False
            record['claimed']=True;return True
    def binding(self,cap):return self._record(cap)['binding']
    def approve_ready(self,cap,ready,executor):
        with self._lock:
            record=self._record(cap)
            if not record or record.get('closed') or not record['claimed'] or record['executor'] is not executor or record['ready'] is not None or type(ready) is not model.SandboxReady:return False
            if ready.binding!=record['binding'] or ready.engine!=self.engine or ready.policy_digest!=self.policy.digest() or not ready.guards_hold():return False
            digest=ready_digest(ready)
            if self.assurance=='host_verified':
                evidence=self.session.verify_ready(record['binding'],ready,executor)
                if type(evidence) is not model.HostReadyEvidence or evidence.binding!=record['binding'] or evidence.ready_digest!=digest or not valid_proof_id(evidence.proof_id):return False
            record['ready']=digest;return True
    def issue_worker_permit(self,lease,raw,executor,now,format):
        """Trusted broker integration only; simulation can never issue this cap.

        A future authenticated worker bootstrap transfers/re-issues child-local
        capability through its own trusted IPC. This Python object is not an IPC
        bearer string and must not be serialized in request JSON.
        """
        with self._lock:
            if self.assurance!='host_verified' or not self.check_lease(lease,raw,executor,now):return None
            record=self._record(lease)
            expected={'openpyxl':'xlsx','python-docx':'docx','python-pptx':'pptx'}[self.engine.engine_id]
            if not record['ready'] or record.get('worker_issued') or format!=expected:return None
            record['worker_issued']=True
            cap=Capability(_SEAL,self)
            self._records[cap]=dict(kind='worker',binding=record['binding'],engine=self.engine,policy=self.policy,
                                    expiry=record['expiry'],source='/input/source.'+format,
                                    candidate='/output/candidate.'+format,used=False)
            return cap
    def consume_worker_permit(self,cap,raw,source,candidate,engine_id,now):
        with self._lock:
            record=self._record(cap)
            if self.assurance!='host_verified' or not record or record['kind']!='worker' or record['used']:return None
            try:
                if (record['binding']!=bind(raw,record['binding'].attempt_id) or record['source']!=source or record['candidate']!=candidate
                        or record['engine'].engine_id!=engine_id or type(now) not in (int,float) or not math.isfinite(now) or now<0 or now>=record['expiry']):return None
            except (TypeError,ValueError):return None
            record['used']=True
            return record['engine'],record['policy'],record['binding']
    def issue_credential(self,lease,raw,executor,now,receipt,candidate_sha,terminal_proof):
        with self._lock:
            if self.assurance!='host_verified' or not self.check_lease(lease,raw,executor,now):return None
            record=self._record(lease)
            if not record['ready'] or record.get('credential_issued') or receipt.get('assurance')!='host_verified' or receipt.get('status')!='candidate_validated':return None
            digest=model.digest(receipt)
            evidence=self.session.verify_terminal(record['binding'],record['ready'],receipt,candidate_sha,terminal_proof,executor)
            if type(evidence) is not model.HostTerminalEvidence or evidence.binding!=record['binding'] or evidence.ready_digest!=record['ready'] or evidence.receipt_digest!=digest or evidence.candidate_sha256!=candidate_sha or not valid_proof_id(evidence.proof_id):return None
            record['credential_issued']=True
            credential=Capability(_SEAL,self)
            self._records[credential]=dict(kind='validator',binding=record['binding'],candidate=candidate_sha,receipt=digest,expiry=record['expiry'],used=False)
            return credential
    def consume_credential(self,cap,raw,candidate_sha,receipt_digest=None,*,now=None):
        with self._lock:
            record=self._record(cap)
            if self.assurance!='host_verified' or not record or record['kind']!='validator' or record['used']:return False
            try:
                if (record['binding']!=bind(raw,record['binding'].attempt_id) or record['candidate']!=candidate_sha or record['receipt']!=receipt_digest
                        or type(now) not in (int,float) or not math.isfinite(now) or now<0 or now>=record['expiry']):return False
            except (ValueError,TypeError):return False
            record['used']=True;return True

    def finish(self,lease,keep_credential=None):
        """Close admission and revoke all child capabilities except accepted result.

        A closed lease can never authorize another ready/spawn/worker/validator.
        The one retained validator still has its original short expiry and must
        be consumed against current host monotonic time plus core CAS checks.
        """
        with self._lock:
            record=self._record(lease)
            if not record or record['kind']!='lease':return
            record['closed']=True
            for cap,child in self._records.items():
                if child['binding']==record['binding'] and child['kind'] in ('worker','validator') and cap is not keep_credential:
                    child['used']=True
