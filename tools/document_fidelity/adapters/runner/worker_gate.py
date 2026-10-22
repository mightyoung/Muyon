"""Host-issued worker permit validation. No JSON/bootstrap flag grants authority."""
from dataclasses import dataclass
from importlib import metadata
from pathlib import Path
import os
import time
from .authority import Capability
from . import model
from ..protocol import parse_request


@dataclass(frozen=True)
class WorkerAdmission:
    request:dict
    engine:model.EngineIdentity
    on_entry:object=None
    def engine_entered(self):
        if self.on_entry is not None:self.on_entry()


def require_worker_permit(permit,job,source,candidate,engine_id):
    try:
        from .linux.worker_permit import RemoteWorkerPermit
        request=parse_request(job)
        if type(permit) is RemoteWorkerPermit:
            engine,policy,binding=permit.consume(request,source,candidate,engine_id)
            from ..runtime import read_regular
            if model.sha(read_regular(source,policy.max_input_bytes))!=binding.source_sha256 or metadata.version(engine.engine_id)!=engine.version:raise ValueError('source_or_engine_changed')
            return WorkerAdmission(request,engine,permit.engine_entered)
        if type(permit) is not Capability:raise ValueError('not_capability')
        issuer=permit._issuer
        if issuer.assurance!='host_verified':raise ValueError('simulation_not_worker_authority')
        result=issuer.consume_worker_permit(permit,request,os.fspath(source),os.fspath(candidate),engine_id,time.monotonic()*1000)
        if result is None:raise ValueError('permit_binding_or_expiry')
        engine,policy,binding=result
        # Authorization is consumed before file access/import; no original path
        # is caller-selected. Kernel RO mounts still require future qualification.
        from ..runtime import read_regular
        data=read_regular(source,policy.max_input_bytes)
        if model.sha(data)!=binding.source_sha256:raise ValueError('source_changed')
        if metadata.version(engine.engine_id)!=engine.version:raise ValueError('engine_version_changed')
        return WorkerAdmission(request,engine)
    except Exception as exc:
        raise RuntimeError('worker_runtime_not_qualified') from exc
