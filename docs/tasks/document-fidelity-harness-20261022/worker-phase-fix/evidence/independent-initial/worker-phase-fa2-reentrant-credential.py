"""Pure synthetic trusted-API reentry; no host credential or isolation evidence."""
import sys,json
sys.path.insert(0,'/tmp/worker-phase-fa2-snapshot')
from tools.document_fidelity.adapters.runner.tests.test_launcher import LauncherTests,FakeHostOS,FakeHostSession
from tools.document_fidelity.adapters.runner import authority,model
T=LauncherTests();T.setUp();nested=[]
a=None;lease=None
receipt=dict(assurance='host_verified',status='candidate_validated',txn_eligible=True)
candidate_sha='a'*64
class S(FakeHostSession):
    inside=False
    def verify_terminal(self,*args):
        if not self.inside:
            self.inside=True
            nested.append(a.issue_credential(lease,T.req,os,os.clock,receipt,candidate_sha,'FAKE_NOT_PRODUCTION'))
        return super().verify_terminal(*args)
os=FakeHostOS();s=S();a=authority.Authority.host(T.engine,T.policy,s)
lease=a.admit(T.req,model.sha(T.source),os,'reentrant_credential',0)
assert a.claim(lease,T.req,os,0)
ready=model.SandboxReady(a.binding(lease),T.engine,T.policy.digest(),True,True,True,True,True,True)
assert a.approve_ready(lease,ready,os)
a.close_worker_stage(lease)
assert a.verify_execution(lease,T.req,os,0,'FAKE_NOT_PRODUCTION')
outer=a.issue_credential(lease,T.req,os,0,receipt,candidate_sha,'FAKE_NOT_PRODUCTION')
results=[a.consume_credential(cap,T.req,candidate_sha,model.digest(receipt),now=0) for cap in [nested[0],outer]]
print(json.dumps(dict(nested_minted=nested[0] is not None,outer_minted=outer is not None,distinct=nested[0] is not outer,both_consumptions=results)))
assert results==[True,True]
assert not any(x in sys.modules for x in ['openpyxl','docx','pptx'])
