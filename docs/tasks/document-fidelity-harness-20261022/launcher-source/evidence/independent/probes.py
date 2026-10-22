"""Explicit fake OS / fake host control-flow probes; no real engine or OS actions."""
import json, sys
sys.path.insert(0, '/workspace/document-fidelity')
from tools.document_fidelity.adapters.runner.tests.test_launcher import FakeOS, LauncherTests
from tools.document_fidelity.adapters.runner import authority, launcher, model

fixture=LauncherTests();fixture.setUp()
source,request,engine,policy=fixture.source,fixture.req,fixture.engine,fixture.policy

class LateReadyFakeOS(FakeOS):
    def ready(self,*args):
        result=super().ready(*args)
        self.clock=policy.timeout_ms+1
        return result
os=LateReadyFakeOS(); a=authority.Authority.simulation(engine,policy)
r=launcher.run_simulation(source,request,os,a)
print(json.dumps(dict(probe='deadline_elapsed_before_spawn',status=r.public['status'],reasons=r.public['reasons'],calls=os.calls,clock=os.clock)))
assert 'spawn' in os.calls and r.public['status']=='timed_out'

class FakeHostOS(FakeOS,model.HostOSBackend):
    """Structural stand-in only; never asserts real host or sandbox qualification."""
    assurance='host_verified'
    def spawn(self,workspace,spec,lease):
        self.lease=lease
        return super().spawn(workspace,spec,lease)
    def terminal_proof(self,process,workspace):return 'EXPLICIT_FAKE_TERMINAL_PROOF'

class FakeHostSession(model.TrustedHostSession):
    """Test-only verifier: all returned evidence is synthetic, not certification."""
    cancelled=False
    cancel_in_verify=False
    expire_in_cleanup=False
    def verify_executor(self,executor):return isinstance(executor,FakeHostOS)
    def verify_admission(self,binding,engine,policy,now_ms):
        return model.HostEvidence(binding,engine,policy.digest(),now_ms+1000,'FAKE','FAKE','FAKE','FAKE')
    def verify_ready(self,binding,ready,executor):
        return model.HostReadyEvidence(binding,authority.ready_digest(ready),'FAKE')
    def verify_terminal(self,binding,ready_digest,receipt,candidate_sha256,proof,executor):
        if self.cancel_in_verify:self.cancelled=True
        return model.HostTerminalEvidence(binding,ready_digest,model.digest(receipt),candidate_sha256,'FAKE')

session=FakeHostSession();session.cancel_in_verify=True
os=FakeHostOS();a=authority.Authority.host(engine,policy,session)
r=launcher.run_production(source,request,launcher.TrustedRuntimeBinding(a,os),cancel=lambda:session.cancelled)
print(json.dumps(dict(probe='cancel_during_final_host_validation',synthetic_host_only=True,status=r.public['status'],txn_eligible=r.public['txn_eligible'],cancelled=session.cancelled,candidate_returned=r.candidate is not None,credential_returned=r.credential is not None)))
assert session.cancelled and r.candidate is not None and r.credential is not None

class SlowCleanupFakeHostOS(FakeHostOS):
    def cleanup(self,workspace):
        super().cleanup(workspace)
        self.clock=policy.timeout_ms+1
session=FakeHostSession();os=SlowCleanupFakeHostOS();a=authority.Authority.host(engine,policy,session)
r=launcher.run_production(source,request,launcher.TrustedRuntimeBinding(a,os))
print(json.dumps(dict(probe='deadline_elapsed_during_cleanup',synthetic_host_only=True,status=r.public['status'],clock=os.clock,timeout_ms=policy.timeout_ms,txn_eligible=r.public['txn_eligible'],candidate_returned=r.candidate is not None)))
assert os.clock>policy.timeout_ms and r.public['txn_eligible']

# Cancelled attempt lease is not terminalized; verify via authority only, no worker execution.
session=FakeHostSession();os=FakeHostOS('cancel');a=authority.Authority.host(engine,policy,session)
r=launcher.run_production(source,request,launcher.TrustedRuntimeBinding(a,os),cancel=lambda:os.poll_count>=1)
permit=a.issue_worker_permit(os.lease,request,os,os.clock,'xlsx')
accepted=a.consume_worker_permit(permit,request,'/input/source.xlsx','/output/candidate.xlsx','openpyxl',os.clock)
print(json.dumps(dict(probe='worker_permit_after_cancel_cleanup',synthetic_host_only=True,status=r.public['status'],cleaned='cleanup' in os.calls,permit_issued=permit is not None,permit_consumed=accepted is not None)))
assert r.public['status']=='cancelled' and accepted is not None

# Time passage does not invalidate an already issued credential (integration observation).
session=FakeHostSession();os=FakeHostOS();a=authority.Authority.host(engine,policy,session)
r=launcher.run_production(source,request,launcher.TrustedRuntimeBinding(a,os))
os.clock=1000000
accepted=a.consume_credential(r.credential,request,r.public['candidate_sha256'],model.digest(r.public))
print(json.dumps(dict(probe='validator_consumption_no_ttl',synthetic_host_only=True,clock=os.clock,admission_expires_ms=1000,accepted=accepted)))
assert accepted
print(json.dumps(dict(third_party_modules_imported=[name for name in ('openpyxl','docx','pptx') if name in sys.modules])))
assert not any(name in sys.modules for name in ('openpyxl','docx','pptx'))
