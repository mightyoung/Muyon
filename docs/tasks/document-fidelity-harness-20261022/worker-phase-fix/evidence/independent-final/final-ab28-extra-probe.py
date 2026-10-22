"""Pure fake host API boundary probes, never real host/runtime evidence."""
import sys,json
sys.path.insert(0,'/tmp/final-ab28-snapshot')
from tools.document_fidelity.adapters.runner.tests.test_launcher import LauncherTests,FakeHostOS,FakeHostSession
from tools.document_fidelity.adapters.runner import authority,launcher,model
T=LauncherTests();T.setUp()
for mode,started,engine in [('spawn_uncertain',None,'unknown'),('spawn_reconciled',True,'unknown'),('reserve_error',False,'not_run'),('exit',True,'unknown')]:
    r,os,a=T.host_contract_fake(FakeHostOS(mode))
    assert r.public['worker_process_started'] is started and r.public['engine_execution']==engine
    assert r.candidate is None and r.credential is None and r.public['txn_eligible'] is False
    print(json.dumps(dict(mode=mode,started=started,engine=engine,status=r.public['status'],calls=os.calls)))
for phase in ['execution','terminal']:
    class Late(FakeHostSession):
        def verify_execution(self,*args):
            evidence=super().verify_execution(*args)
            if phase=='execution':args[-1].clock=51
            return evidence
        def verify_terminal(self,*args):
            evidence=super().verify_terminal(*args)
            if phase=='terminal':args[-1].clock=51
            return evidence
    r,os,a=T.host_contract_fake(session=Late())
    assert r.public['status']=='timed_out' and r.candidate is None and r.credential is None and not r.public['txn_eligible']
    print(json.dumps(dict(mode=phase+'_operation_deadline',status=r.public['status'],reasons=r.public['reasons'])))
# Missing engine-entry observation is HOLD for default abstract-contract implementation.
class Missing(FakeHostSession):
    verify_execution=model.TrustedHostSession.verify_execution
r,os,a=T.host_contract_fake(session=Missing())
assert r.public['status']=='held' and r.credential is None and r.candidate is None and not r.public['txn_eligible']
print(json.dumps(dict(mode='default_missing_execution',status=r.public['status'],reasons=r.public['reasons'])))
# Terminal verifier failure consumes its only issuance attempt, never makes retry authority.
for fail in ['none','exception']:
    class Fail(FakeHostSession):
        calls=0
        def verify_terminal(self,*args):
            self.calls+=1
            if fail=='exception':raise RuntimeError('synthetic verification failure')
            return None
    os=FakeHostOS();s=Fail();a=authority.Authority.host(T.engine,T.policy,s)
    lease=a.admit(T.req,model.sha(T.source),os,'failure_'+fail,0);assert a.claim(lease,T.req,os,0)
    ready=model.SandboxReady(a.binding(lease),T.engine,T.policy.digest(),True,True,True,True,True,True)
    assert a.approve_ready(lease,ready,os);a.close_worker_stage(lease)
    assert a.verify_execution(lease,T.req,os,0,'FAKE_NOT_PRODUCTION')
    receipt=dict(assurance='host_verified',status='candidate_validated',txn_eligible=True)
    caps=[]
    for _ in range(2):
        try:cap=a.issue_credential(lease,T.req,os,0,receipt,'a'*64,'FAKE_NOT_PRODUCTION')
        except RuntimeError:cap=None
        caps.append(cap)
    assert caps==[None,None] and s.calls==1
    print(json.dumps(dict(mode='terminal_failure_'+fail,callback_calls=s.calls,issued=[cap is not None for cap in caps])))
assert not any(x in sys.modules for x in ['openpyxl','docx','pptx'])
print('PASS: uncertain spawn truthfulness, operation deadlines, missing execution HOLD, failed issuance no-retry.')
