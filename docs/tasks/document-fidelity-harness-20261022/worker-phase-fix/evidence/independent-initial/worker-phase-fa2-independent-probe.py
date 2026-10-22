"""Synthetic trusted-API probes only. No engine, worker CLI, subprocess or OS isolation."""
import sys,json
sys.path.insert(0,'/tmp/worker-phase-fa2-snapshot')
from tools.document_fidelity.adapters.runner.tests.test_launcher import LauncherTests,FakeHostOS,FakeHostSession
from tools.document_fidelity.adapters.runner import authority,launcher,model
T=LauncherTests();T.setUp()
rows=[]
def run(mode):
    a=None
    class S(FakeHostSession):
        def verify_admission(self,binding,engine,policy,now):
            if mode.endswith('ttl'):return model.HostEvidence(binding,engine,policy.digest(),15,*(['FAKE_NOT_PRODUCTION']*4))
            return super().verify_admission(binding,engine,policy,now)
        def verify_ready(self,binding,ready,executor):
            evidence=super().verify_ready(binding,ready,executor)
            if mode=='ready_close_worker':a.close_worker_stage(next(iter(a._records)))
            if mode=='ready_finish':a.finish(next(iter(a._records)))
            return evidence
        def verify_execution(self,binding,engine,proof,executor):
            evidence=super().verify_execution(binding,engine,proof,executor)
            if mode=='execution_ttl':executor.clock=20
            if mode=='execution_finish':a.finish(executor.lease)
            return evidence
        def verify_terminal(self,*args):
            evidence=super().verify_terminal(*args)
            if mode=='terminal_ttl':args[-1].clock=20
            if mode=='terminal_finish':a.finish(args[-1].lease)
            return evidence
    os=FakeHostOS();s=S();a=authority.Authority.host(T.engine,T.policy,s)
    def cancel():
        if mode=='cancel_closes_worker_returns_false' and a._records and next(iter(a._records.values())).get('ready'):
            a.close_worker_stage(next(iter(a._records)))
        return False
    r=launcher.run_production(T.source,T.req,launcher.TrustedRuntimeBinding(a,os),cancel=cancel)
    row=dict(mode=mode,status=r.public['status'],reasons=r.public['reasons'],spawn='spawn' in os.calls,engine=r.public['engine_execution'],candidate=r.candidate is not None,credential=r.credential is not None,eligible=r.public['txn_eligible'],clock=os.clock)
    rows.append(row);print(json.dumps(row,sort_keys=True))
for mode in ['normal','ready_close_worker','ready_finish','cancel_closes_worker_returns_false','execution_ttl','execution_finish','terminal_ttl','terminal_finish']:run(mode)
assert rows[0]['status']=='candidate_validated' and rows[0]['credential']
for i in [4,5,6,7]:assert not rows[i]['candidate'] and not rows[i]['credential'] and not rows[i]['eligible']
assert rows[1]['spawn'], 'Frozen SHA should reproduce missing post-ready worker-phase check'
assert not any(x in sys.modules for x in ['openpyxl','docx','pptx'])
print('PASS: normal path and execution/terminal TTL/close checks; REPRODUCED: ready callback phase close still spawns.')
