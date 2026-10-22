"""Typed runner contracts. JSON audit records never become capabilities."""
from dataclasses import dataclass,asdict
import hashlib
import json
import math
import re
from abc import ABC,abstractmethod


def digest(value):
    return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=True,allow_nan=False).encode()).hexdigest()


def sha(value):return hashlib.sha256(value).hexdigest()


@dataclass(frozen=True)
class Policy:
    timeout_ms:int=30000
    grace_ms:int=100
    poll_ms:int=25
    max_stdout_bytes:int=32768
    max_stderr_bytes:int=32768
    max_candidate_bytes:int=8388608
    max_input_bytes:int=16777216
    max_chunk_bytes:int=65536
    cpu_seconds:int=20
    address_space_bytes:int=536870912
    max_pids:int=8
    def __post_init__(self):
        caps=(30000,1000,100,32768,32768,8388608,16777216,65536,20,536870912,8)
        if any(type(v) is not int or not 0<v<=c for v,c in zip(asdict(self).values(),caps)):
            raise ValueError('policy_can_only_tighten_hard_caps')
    def digest(self):return digest(asdict(self))


@dataclass(frozen=True)
class EngineIdentity:
    engine_id:str
    version:str
    artifact_sha256:str
    worker_sha256:str
    runtime_sha256:str
    def __post_init__(self):
        if self.engine_id not in ('openpyxl','python-docx','python-pptx') or not isinstance(self.version,str) or not re.fullmatch(r'[0-9A-Za-z.+-]{1,32}',self.version):raise ValueError('invalid_engine')
        if any(not isinstance(v,str) or not re.fullmatch(r'[0-9a-f]{64}',v) for v in (self.artifact_sha256,self.worker_sha256,self.runtime_sha256)):raise ValueError('invalid_artifact_hash')


@dataclass(frozen=True)
class Binding:
    attempt_id:str
    request_digest:str
    source_sha256:str
    identity:tuple


@dataclass(frozen=True)
class SandboxReady:
    binding:Binding
    engine:EngineIdentity
    policy_digest:str
    source_read_only:bool
    job_read_only:bool
    no_network:bool
    private_output:bool
    sanitized_environment:bool
    limits_enforced:bool
    proof:object=None
    def guards_hold(self):return all(v is True for v in (self.source_read_only,self.job_read_only,self.no_network,self.private_output,self.sanitized_environment,self.limits_enforced))


@dataclass(frozen=True)
class Event:
    kind:str
    data:bytes=b''
    exit_code:object=None


@dataclass(frozen=True)
class OutputState:
    candidate_bytes:int
    extra_files:bool


@dataclass(frozen=True)
class Snapshot:
    candidate:bytes
    source:bytes
    job:bytes
    regular:bool
    link_count:int
    extra_files:bool


@dataclass(frozen=True)
class Reconciliation:
    known:bool
    workspace:object
    process:object


@dataclass(frozen=True)
class HostEvidence:
    """Only the separately trusted host channel may supply this typed record.

    Constructor/type alone is not trust: Authority also requires its registered
    TrustedHostSession, executor identity, exact bindings and independent ready/
    terminal proof. Arbitrary Python inside that trusted service is outside the
    JSON/model threat boundary.
    """
    binding:Binding
    engine:EngineIdentity
    policy_digest:str
    expires_ms:float
    provenance_review_id:str
    license_review_id:str
    scope_review_id:str
    isolation_attestation_id:str


@dataclass(frozen=True)
class HostReadyEvidence:
    binding:Binding
    ready_digest:str
    proof_id:str


@dataclass(frozen=True)
class HostExecutionEvidence:
    """Authenticated worker engine-entry observation, never a spawn receipt.

    Only TrustedHostSession may corroborate proof against the exact engine
    artifact/runtime/worker and attempt binding. Typed construction is not trust.
    """
    binding:Binding
    engine:EngineIdentity
    proof_id:str


@dataclass(frozen=True)
class HostTerminalEvidence:
    binding:Binding
    ready_digest:str
    receipt_digest:str
    candidate_sha256:str
    proof_id:str


class TrustedHostSession(ABC):
    """Trusted application bootstrap interface; never constructed from request JSON.

    Implementations must authenticate native/broker proofs, pin evidence/artifacts,
    authorize scope/revision and enforce operation/idempotency policy externally.
    There is deliberately no implementation or bootstrap connection here.
    """
    @abstractmethod
    def verify_executor(self,executor):pass
    @abstractmethod
    def verify_admission(self,binding,engine,policy,now_ms):pass
    @abstractmethod
    def verify_ready(self,binding,ready,executor):pass
    def verify_execution(self,binding,engine,proof,executor):
        # Missing authenticated worker observation never implies engine entry.
        return None
    @abstractmethod
    def verify_terminal(self,binding,ready_digest,receipt,candidate_sha256,proof,executor):pass


class HostOSBackend(ABC):
    """Future authenticated OS backend, not an ambient subprocess fallback.

    reserve stages fixed paths RO input/job, private output, sanitized environment,
    no network, pinned artifact/runtime/worker and kernel limits before spawn.
    ready/proofs must be corroborated by TrustedHostSession. poll must wait bounded
    time/read bounded chunks; measure and snapshot use stable no-follow handles.
    terminate/kill/reap target nonce-bound process tree (pidfd/cgroup equivalent),
    not a reused numeric PID. Reconcile never re-spawns. No implementation exists
    in the currently refused namespace environment.
    """
    assurance='host_verified'
    @abstractmethod
    def now_ms(self):pass
    @abstractmethod
    def reserve(self,attempt,spec,source,job):pass
    @abstractmethod
    def ready(self,workspace,binding,engine,policy):pass
    @abstractmethod
    def spawn(self,workspace,spec,lease):pass
    @abstractmethod
    def reconcile(self,attempt):pass
    @abstractmethod
    def poll(self,process,wait_ms):pass
    @abstractmethod
    def measure(self,workspace):pass
    @abstractmethod
    def terminate_tree(self,process):pass
    @abstractmethod
    def kill_tree(self,process):pass
    @abstractmethod
    def reap_tree(self,process,wait_ms):pass
    @abstractmethod
    def snapshot(self,workspace,policy):pass
    @abstractmethod
    def terminal_proof(self,process,workspace):pass
    @abstractmethod
    def cleanup(self,workspace):pass
    @abstractmethod
    def quarantine(self,attempt,workspace=None):pass


@dataclass
class Result:
    public:dict
    credential:object=None
    candidate:object=None
