"""Fake OS only: no subprocess, namespace, engine or worker CLI executed."""
import hashlib,io,json,sys,unittest,zipfile
from dataclasses import replace
from tools.document_fidelity.adapters.runner import authority,launcher,model,worker_gate
from tools.document_fidelity.complex_fixtures import build_complex_samples
from tools.document_fidelity.tests.test_adapter import request,edit_bytes

class FakeOS:
    assurance='simulation'
    def __init__(self,mode='ok'):
        self.mode=mode;self.clock=0;self.calls=[];self.poll_count=0;self.live=False
    def now_ms(self):return self.clock
    def reserve(self,attempt,spec,source,job):
        self.calls.append('reserve');self.attempt=attempt;self.spec=spec;self.source=source;self.job=job
        if self.mode=='reserve_error':raise RuntimeError('fake reserve failure')
        return 'workspace'
    def ready(self,workspace,binding,engine,policy):
        self.calls.append('ready')
        ready=model.SandboxReady(binding,engine,policy.digest(),True,True,True,True,True,True)
        if self.mode=='network':ready=replace(ready,no_network=False)
        if self.mode=='wrong_artifact':ready=replace(ready,engine=replace(engine,artifact_sha256='f'*64))
        return ready
    def spawn(self,workspace,spec,lease):
        self.calls.append('spawn');self.live=True
        if self.mode in ('spawn_uncertain','spawn_reconciled'):raise RuntimeError('uncertain spawn')
        return 'process'
    def reconcile(self,attempt):
        self.calls.append('reconcile')
        if self.mode in ('spawn_uncertain','reserve_error'):return model.Reconciliation(False,None,None)
        return model.Reconciliation(True,'workspace','process' if self.live else None)
    def poll(self,process,wait_ms):
        self.calls.append('poll');self.poll_count+=1;self.clock+=wait_ms
        if self.mode=='clock_back':self.clock=-1
        if self.mode=='exception':raise RuntimeError('fake poll failure')
        if self.mode=='timeout':return model.Event('running')
        if self.mode=='stdout':return model.Event('stdout',data=b'x'*17)
        if self.mode=='stderr':return model.Event('stderr',data=b'x'*17)
        if self.mode=='chunk':return model.Event('stdout',data=b'x'*70000)
        if self.mode=='unknown_event':return model.Event('unexpected')
        if self.mode in ('cancel','term_error') and self.poll_count==1:return model.Event('running')
        return model.Event('exit',exit_code=1 if self.mode=='exit' else 0)
    def measure(self,workspace):
        self.calls.append('measure')
        return model.OutputState(70000 if self.mode=='output_limit' else 0,False)
    def terminate_tree(self,process):
        self.calls.append('terminate')
        if self.mode=='term_error':raise RuntimeError('fake TERM failure')
    def kill_tree(self,process):self.calls.append('kill')
    def reap_tree(self,process,wait_ms):
        self.calls.append('reap')
        if self.mode=='reap_unknown':return False
        if self.mode=='needs_kill' and 'kill' not in self.calls:return False
        self.live=False;return True
    def snapshot(self,workspace,policy):
        self.calls.append('snapshot')
        data=edit_bytes(self.source,'drop' if self.mode=='unknown_part' else 'ok')
        return model.Snapshot(data,self.source if self.mode!='source_changed' else b'bad',self.job,
                              self.mode!='symlink',1,self.mode=='extra')
    def cleanup(self,workspace):self.calls.append('cleanup')
    def quarantine(self,attempt,workspace=None):self.calls.append('quarantine')

class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.source=build_complex_samples()['complex.xlsx'];self.req=request(self.source)
        self.policy=model.Policy(timeout_ms=50,grace_ms=5,poll_ms=10,max_stdout_bytes=16,max_stderr_bytes=16,max_candidate_bytes=65536)
        self.engine=model.EngineIdentity('openpyxl','3.1.5','1'*64,'2'*64,'3'*64)
    def simulate(self,mode='ok',cancel=None):
        os=FakeOS(mode);a=authority.Authority.simulation(self.engine,self.policy)
        result=launcher.run_simulation(self.source,self.req,os,a,cancel=cancel)
        return result,os,a
    def test_production_default_and_plain_json_can_never_open_execution(self):
        for binding in (None,{'verified':True,'isolation':True}, {'receipt_kind':'host_validated','txn_eligible':True}):
            os=FakeOS();r=launcher.run_production(self.source,self.req,binding,os)
            self.assertEqual('held',r.public['status']);self.assertIsNone(r.credential);self.assertFalse(os.calls)
    def test_full_fake_lifecycle_receipt_is_never_txn_eligible(self):
        r,os,a=self.simulate()
        self.assertEqual('simulated_validated',r.public['status'],r.public)
        self.assertEqual(3,r.public['receipt_version']);self.assertEqual('simulation',r.public['assurance'])
        self.assertFalse(r.public['txn_eligible']);self.assertIsNone(r.credential)
        self.assertEqual('not_run',r.public['engine_execution']);self.assertEqual('pass',r.public['validation']['status'])
        self.assertLess(os.calls.index('reap'),os.calls.index('snapshot'))
        self.assertIn('cleanup',os.calls);self.assertNotIn('quarantine',os.calls)
        self.assertEqual(['/runtime/python3','-I','-B','-m','tools.document_fidelity.adapters.runner.worker_entry','--format','xlsx'],os.spec['argv'])
        self.assertFalse(a.consume_credential(r.public,self.req,r.public['candidate_sha256']))
        self.assertNotIn('openpyxl',sys.modules)
    def test_missing_ready_and_wrong_engine_proof_never_spawn(self):
        for mode in ('network','wrong_artifact'):
            with self.subTest(mode=mode):
                r,os,_=self.simulate(mode);self.assertEqual('failed',r.public['status']);self.assertNotIn('spawn',os.calls)
    def test_cancel_before_spawn_and_running_are_reaped(self):
        r,os,_=self.simulate(cancel=lambda:True)
        self.assertEqual('cancelled',r.public['status']);self.assertNotIn('spawn',os.calls)
        os=FakeOS('cancel');a=authority.Authority.simulation(self.engine,self.policy)
        r=launcher.run_simulation(self.source,self.req,os,a,cancel=lambda:os.poll_count>=1)
        self.assertEqual('cancelled',r.public['status']);self.assertIn('terminate',os.calls);self.assertIn('reap',os.calls);self.assertNotIn('snapshot',os.calls)
    def test_time_logs_outputs_exit_and_exception_fail_closed(self):
        for mode in ('timeout','stdout','stderr','chunk','output_limit','exit','exception','clock_back','unknown_event'):
            with self.subTest(mode=mode):
                r,os,_=self.simulate(mode);self.assertIn(r.public['status'],('timed_out','failed'))
                self.assertIn('reap',os.calls);self.assertNotIn('snapshot',os.calls);self.assertIsNone(r.credential)
    def test_kill_reap_and_uncertain_reap_quarantine(self):
        r,os,_=self.simulate('needs_kill')
        self.assertIn('kill',os.calls);self.assertEqual('failed',r.public['status']);self.assertNotIn('snapshot',os.calls)
        r,os,_=self.simulate('reap_unknown')
        self.assertEqual('outcome_unknown',r.public['status']);self.assertIn('quarantine',os.calls);self.assertNotIn('cleanup',os.calls)
    def test_spawn_uncertainty_reconciles_without_retry(self):
        for mode in ('spawn_uncertain','spawn_reconciled','reserve_error'):
            with self.subTest(mode=mode):
                r,os,_=self.simulate(mode);self.assertIn('reconcile',os.calls);self.assertLessEqual(os.calls.count('spawn'),1)
                if mode!='spawn_reconciled':
                    self.assertEqual('outcome_unknown',r.public['status']);self.assertIn('quarantine',os.calls)
                else:self.assertIn('reap',os.calls);self.assertEqual('failed',r.public['status'])
    def test_snapshot_source_links_and_unknown_parts_fail_validation(self):
        for mode in ('unknown_part','source_changed','symlink','extra'):
            with self.subTest(mode=mode):
                r,os,_=self.simulate(mode);self.assertEqual('failed',r.public['status']);self.assertIsNone(r.credential)
                self.assertLess(os.calls.index('reap'),os.calls.index('snapshot'))
    def test_cancellation_during_snapshot_discards_candidate(self):
        os=FakeOS();a=authority.Authority.simulation(self.engine,self.policy)
        result=launcher.run_simulation(self.source,self.req,os,a,cancel=lambda:'snapshot' in os.calls)
        self.assertEqual('cancelled',result.public['status']);self.assertIsNone(result.candidate)
        self.assertIn('cleanup',os.calls);self.assertIsNone(result.credential)
    def test_terminate_failure_still_attempts_kill_and_reap(self):
        os=FakeOS('term_error');a=authority.Authority.simulation(self.engine,self.policy)
        result=launcher.run_simulation(self.source,self.req,os,a,cancel=lambda:os.poll_count>=1)
        self.assertEqual('cancelled',result.public['status']);self.assertIn('kill',os.calls)
        self.assertTrue(result.public['reaped']);self.assertIn('cleanup',os.calls)
    def test_ready_transition_is_single_use_and_guards_are_strict_booleans(self):
        a=authority.Authority.simulation(self.engine,self.policy);os=FakeOS()
        cap=a.admit(self.req,model.sha(self.source),os,'attempt_ready',0)
        self.assertTrue(a.claim(cap,self.req,os,0))
        ready=model.SandboxReady(a.binding(cap),self.engine,self.policy.digest(),True,True,True,True,True,True)
        self.assertFalse(a.approve_ready(cap,replace(ready,no_network='true'),os))
        self.assertTrue(a.approve_ready(cap,ready,os))
        self.assertFalse(a.approve_ready(cap,ready,os))
        self.assertIsNone(a.issue_worker_permit(cap,self.req,os,0,'xlsx'))
    def test_policy_only_tightens_and_no_json_host_session_or_opaque_factory(self):
        for values in ({'max_pids':9},{'timeout_ms':True},{'max_input_bytes':0}):
            with self.assertRaises(ValueError):model.Policy(**values)
        with self.assertRaises(TypeError):authority.Authority.host(self.engine,self.policy,{'verified':True})
        with self.assertRaises(TypeError):authority.Capability()
    def test_scope_expiry_and_replay_and_simulated_worker_permits(self):
        a=authority.Authority.simulation(self.engine,self.policy);os=FakeOS()
        lease=a.admit(self.req,hashlib.sha256(self.source).hexdigest(),os,'attempt1',0)
        self.assertIsNotNone(lease)
        wrong=json.loads(json.dumps(self.req));wrong['scope_id']='other'
        self.assertFalse(a.check_lease(lease,wrong,os,0));self.assertFalse(a.check_lease(lease,self.req,os,1000000))
        self.assertTrue(a.claim(lease,self.req,os,0));self.assertFalse(a.claim(lease,self.req,os,0))
        for worker_name in ('openpyxl_worker','docx_worker','pptx_worker'):
            from importlib import import_module
            worker=import_module('tools.document_fidelity.adapters.'+worker_name)
            for fake_permit in (None,{},lease,{'host_verified':True}):
                with self.assertRaises(RuntimeError):worker.edit_copy(self.req,None,None,permit=fake_permit)
        self.assertNotIn('openpyxl',sys.modules);self.assertNotIn('docx',sys.modules);self.assertNotIn('pptx',sys.modules)

if __name__=='__main__':unittest.main()
