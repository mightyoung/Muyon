"""Trusted application factory; no environment/JSON/bootstrap boolean installer."""
from dataclasses import dataclass
from ..authority import Authority
from ..launcher import TrustedRuntimeBinding
from .backend import LinuxBackend
from .kernel import PinnedConfig
from .session import LinuxHostSession,LocalScopeTable

@dataclass(frozen=True)
class Provisioning:
    binding:object
    status:str
    reason:str

def provision(config=None,scopes=None):
    if type(config) is not PinnedConfig or type(scopes) is not LocalScopeTable:
        return Provisioning(None,'held','trusted_pinned_config_and_scope_records_required')
    backend=LinuxBackend(config);session=LinuxHostSession(backend,scopes)
    if not session.verify_executor(backend):return Provisioning(None,'held','native_resource_artifact_or_broker_qualification_missing')
    authority=Authority.host(config.engine,config.policy,session)
    return Provisioning(TrustedRuntimeBinding(authority,backend),'provisioned','native_observations_required_per_attempt')
