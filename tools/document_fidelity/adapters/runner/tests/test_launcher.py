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

class FakeHostOS(FakeOS,model.HostOSBackend):
    """Test double for trusted API contract; NEVER real host/sandbox evidence."""
    assurance='host_verified'
    def spawn(self,workspace,spec,lease):
        self.lease=lease
        return super().spawn(workspace,spec,lease)
    def terminal_proof(self,process,workspace):return 'FAKE_NOT_PRODUCTION'

class FakeHostSession(model.TrustedHostSession):
    """Explicit test bootstrap only; credentials in these tests are synthetic."""
    cancelled=False
    cancel_in_verify=False
    def verify_executor(self,executor):return isinstance(executor,FakeHostOS)
    def verify_admission(self,binding,engine,policy,now_ms):
        return model.HostEvidence(binding,engine,policy.digest(),now_ms+1000,*(['FAKE_NOT_PRODUCTION']*4))
    def verify_ready(self,binding,ready,executor):
        return model.HostReadyEvidence(binding,authority.ready_digest(ready),'FAKE_NOT_PRODUCTION')
    def verify_execution(self,binding,engine,proof,executor):
        return model.HostExecutionEvidence(binding,engine,'FAKE_NOT_PRODUCTION')
    def verify_terminal(self,binding,ready_digest,receipt,candidate_sha256,proof,executor):
        if self.cancel_in_verify:self.cancelled=True
        return model.HostTerminalEvidence(binding,ready_digest,model.digest(receipt),candidate_sha256,'FAKE_NOT_PRODUCTION')

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
    def host_contract_fake(self,os=None,session=None,cancel=None):
        os=os or FakeHostOS();session=session or FakeHostSession()
        a=authority.Authority.host(self.engine,self.policy,session)
        r=launcher.run_production(self.source,self.req,launcher.TrustedRuntimeBinding(a,os),cancel=cancel)
        return r,os,a
    def test_deadline_before_spawn_and_after_cleanup_prevents_release(self):
        class LateReady(FakeOS):
            def ready(os,*args):
                result=super().ready(*args);os.clock=51;return result
        os=LateReady();a=authority.Authority.simulation(self.engine,self.policy)
        r=launcher.run_simulation(self.source,self.req,os,a)
        self.assertEqual('timed_out',r.public['status']);self.assertNotIn('spawn',os.calls)
        class LateCleanup(FakeHostOS):
            def cleanup(os,workspace):super().cleanup(workspace);os.clock=51
        r,os,a=self.host_contract_fake(LateCleanup())
        self.assertEqual('timed_out',r.public['status']);self.assertIsNone(r.credential);self.assertIsNone(r.candidate)
    def test_terminal_host_callback_cancellation_revokes_synthetic_capability(self):
        session=FakeHostSession();session.cancel_in_verify=True
        r,os,a=self.host_contract_fake(session=session,cancel=lambda:session.cancelled)
        self.assertEqual('cancelled',r.public['status']);self.assertIsNone(r.candidate);self.assertIsNone(r.credential)
        self.assertFalse(r.public['txn_eligible'])
    def test_terminal_lease_cannot_mint_worker_permit_and_credential_has_expiry(self):
        os=FakeHostOS('cancel')
        r,os,a=self.host_contract_fake(os,cancel=lambda:os.poll_count>=1)
        self.assertEqual('cancelled',r.public['status'])
        self.assertIsNone(a.issue_worker_permit(os.lease,self.req,os,os.clock,'xlsx'))
        self.assertFalse(a.check_lease(os.lease,self.req,os,os.clock))
        r,os,a=self.host_contract_fake()
        self.assertIsNotNone(r.credential) # synthetic object from explicit fake trusted API only
        self.assertFalse(a.consume_credential(r.credential,self.req,r.public['candidate_sha256'],model.digest(r.public),now=1001))
        self.assertFalse(a.consume_credential(r.credential,self.req,r.public['candidate_sha256'],model.digest(r.public)))
        self.assertFalse(a.consume_credential(r.credential,self.req,r.public['candidate_sha256'],model.digest(r.public),now=-1))
        self.assertTrue(a.consume_credential(r.credential,self.req,r.public['candidate_sha256'],model.digest(r.public),now=os.clock))
        self.assertFalse(a.consume_credential(r.credential,self.req,r.public['candidate_sha256'],model.digest(r.public),now=os.clock))
    def test_docx_and_pptx_fake_os_pipeline_remains_inert(self):
        from tools.document_fidelity.tests.test_text_subsets import subset_samples,text_request,rewrite
        class TextOS(FakeOS):
            def snapshot(os,workspace,policy):
                os.calls.append('snapshot')
                fmt=os.spec['format'];part='word/document.xml' if fmt=='docx' else 'ppt/slides/slide1.xml'
                data=rewrite(os.source,part,lambda payload:payload.replace(b'>target<',b'>edited<'))
                return model.Snapshot(data,os.source,os.job,True,1,False)
        for fmt,name,engine,version in [('docx','simple-run.docx','python-docx','1.2.0'),('pptx','simple-shape.pptx','python-pptx','1.0.2')]:
            with self.subTest(format=fmt):
                source=subset_samples()[name];req=text_request(source,fmt);os=TextOS()
                a=authority.Authority.simulation(model.EngineIdentity(engine,version,'1'*64,'2'*64,'3'*64),self.policy)
                r=launcher.run_simulation(source,req,os,a)
                self.assertEqual('simulated_validated',r.public['status'],r.public)
                self.assertIsNone(r.credential);self.assertFalse(r.public['txn_eligible'])
                self.assertEqual('not_run',r.public['engine_execution'])
                self.assertLess(os.calls.index('reap'),os.calls.index('snapshot'))
        self.assertFalse(any(name in sys.modules for name in ('openpyxl','docx','pptx')))
    def test_fake_trusted_interface_requires_strict_executor_and_proof_shapes(self):
        class TruthyExecutorSession(FakeHostSession):
            def verify_executor(self,executor):return 'true'
        r,os,a=self.host_contract_fake(session=TruthyExecutorSession())
        self.assertEqual('held',r.public['status']);self.assertNotIn('reserve',os.calls)
        class TruthyProofSession(FakeHostSession):
            def verify_ready(self,binding,ready,executor):
                return model.HostReadyEvidence(binding,authority.ready_digest(ready),True)
        r,os,a=self.host_contract_fake(session=TruthyProofSession())
        self.assertEqual('failed',r.public['status']);self.assertNotIn('spawn',os.calls)
    def test_admission_registry_is_bounded_without_eviction_or_replay(self):
        a=authority.Authority.simulation(self.engine,self.policy);os=FakeOS()
        for i in range(1024):self.assertIsNotNone(a.admit(self.req,model.sha(self.source),os,'attempt_'+str(i),0))
        self.assertIsNone(a.admit(self.req,model.sha(self.source),os,'overflow',0))
        self.assertIsNone(a.admit(self.req,model.sha(self.source),os,'attempt_0',0))
    def test_terminal_close_revokes_preissued_worker_and_slow_verifier(self):
        a=None
        class IssuedWorkerOS(FakeHostOS):
            def spawn(os,workspace,spec,lease):
                os.permit=a.issue_worker_permit(lease,self.req,os,os.clock,'xlsx')
                return super().spawn(workspace,spec,lease)
        os=IssuedWorkerOS('cancel');session=FakeHostSession();a=authority.Authority.host(self.engine,self.policy,session)
        r=launcher.run_production(self.source,self.req,launcher.TrustedRuntimeBinding(a,os),cancel=lambda:os.poll_count>=1)
        self.assertIsNotNone(os.permit)
        self.assertIsNone(a.consume_worker_permit(os.permit,self.req,'/input/source.xlsx','/output/candidate.xlsx','openpyxl',os.clock))
        class SlowVerifier(FakeHostSession):
            def verify_terminal(session,*args):
                result=super().verify_terminal(*args);args[-1].clock=51;return result
        r,os,a=self.host_contract_fake(session=SlowVerifier())
        self.assertEqual('timed_out',r.public['status']);self.assertIsNone(r.credential);self.assertFalse(r.public['txn_eligible'])
    def test_stopping_and_cleanup_callbacks_cannot_issue_or_consume_worker(self):
        for mode in ('cancel','ok','reap_unknown','spawn_reconciled'):
            for preissued in (False,True):
                with self.subTest(mode=mode,preissued=preissued):
                    a=None;observations=[]
                    class WindowOS(FakeHostOS):
                        def spawn(os,workspace,spec,lease):
                            os.lease=lease
                            os.saved=a.issue_worker_permit(lease,self.req,os,os.clock,'xlsx') if preissued else None
                            return super().spawn(workspace,spec,lease)
                        def probe(os,stage):
                            issued=a.issue_worker_permit(os.lease,self.req,os,os.clock,'xlsx')
                            consumed=a.consume_worker_permit(os.saved if preissued else issued,self.req,'/input/source.xlsx','/output/candidate.xlsx','openpyxl',os.clock)
                            observations.append((stage,issued is not None,consumed is not None))
                        def terminate_tree(os,process):os.probe('terminate');return super().terminate_tree(process)
                        def kill_tree(os,process):os.probe('kill');return super().kill_tree(process)
                        def reap_tree(os,process,wait_ms):os.probe('reap');return super().reap_tree(process,wait_ms)
                        def cleanup(os,workspace):os.probe('cleanup');return super().cleanup(workspace)
                        def quarantine(os,attempt,workspace=None):os.probe('quarantine');return super().quarantine(attempt,workspace)
                        def reconcile(os,attempt):os.probe('reconcile');return super().reconcile(attempt)
                    os=WindowOS(mode);session=FakeHostSession();a=authority.Authority.host(self.engine,self.policy,session)
                    r=launcher.run_production(self.source,self.req,launcher.TrustedRuntimeBinding(a,os),cancel=lambda:mode=='cancel' and os.poll_count>=1)
                    self.assertTrue(observations)
                    self.assertTrue(all(not issued and not consumed for stage,issued,consumed in observations),observations)
                    if mode=='ok':
                        self.assertEqual('candidate_validated',r.public['status'],r.public)
                        self.assertIsNotNone(r.credential) # synthetic trusted-interface unit object only
                        self.assertTrue(a.consume_credential(r.credential,self.req,r.public['candidate_sha256'],model.digest(r.public),now=os.clock))
    def test_admission_expiry_during_terminal_callback_cannot_report_success(self):
        class ShortLeaseSession(FakeHostSession):
            def verify_admission(session,binding,engine,policy,now_ms):
                return model.HostEvidence(binding,engine,policy.digest(),15,*(['FAKE_NOT_PRODUCTION']*4))
            def verify_terminal(session,*args):
                result=super().verify_terminal(*args);args[-1].clock=20;return result
        r,os,a=self.host_contract_fake(session=ShortLeaseSession())
        self.assertLess(os.clock,self.policy.timeout_ms)
        self.assertNotEqual('candidate_validated',r.public['status']);self.assertFalse(r.public['txn_eligible'])
        self.assertIsNone(r.candidate);self.assertIsNone(r.credential)
    def test_spawn_is_not_evidence_of_third_party_engine_execution(self):
        r,os,a=self.host_contract_fake(FakeHostOS('exit'))
        self.assertEqual('failed',r.public['status'])
        self.assertNotEqual('executed',r.public['engine_execution'])
        self.assertTrue(r.public['worker_process_started'])
        self.assertFalse(any(name in sys.modules for name in ('openpyxl','docx','pptx')))
    def test_missing_or_mismatched_authenticated_engine_observation_is_hold(self):
        for kind in ('missing','json','wrong_engine','wrong_scope'):
            class UnqualifiedExecution(FakeHostSession):
                def verify_execution(session,binding,engine,proof,executor):
                    if kind=='missing':return None
                    if kind=='json':return {'engine_execution':'executed','verified':True}
                    if kind=='wrong_engine':return model.HostExecutionEvidence(binding,replace(engine,artifact_sha256='f'*64),'FAKE_NOT_PRODUCTION')
                    return model.HostExecutionEvidence(replace(binding,request_digest='f'*64),engine,'FAKE_NOT_PRODUCTION')
            r,os,a=self.host_contract_fake(session=UnqualifiedExecution())
            self.assertEqual('held',r.public['status'],r.public)
            self.assertEqual('unknown',r.public['engine_execution']);self.assertIsNone(r.credential);self.assertIsNone(r.candidate)
            self.assertTrue(r.public['worker_process_started']);self.assertFalse(r.public['txn_eligible'])
        self.assertFalse(any(name in sys.modules for name in ('openpyxl','docx','pptx')))
    def test_worker_stage_close_is_irreversible_without_closing_validation_lease(self):
        session=FakeHostSession();os=FakeHostOS();a=authority.Authority.host(self.engine,self.policy,session)
        lease=a.admit(self.req,model.sha(self.source),os,'phase_test',0)
        self.assertTrue(a.claim(lease,self.req,os,0))
        ready=model.SandboxReady(a.binding(lease),self.engine,self.policy.digest(),True,True,True,True,True,True)
        self.assertTrue(a.approve_ready(lease,ready,os))
        permit=a.issue_worker_permit(lease,self.req,os,0,'xlsx');self.assertIsNotNone(permit)
        self.assertTrue(a.close_worker_stage(lease));self.assertFalse(a.close_worker_stage(lease))
        self.assertTrue(a.check_lease(lease,self.req,os,0))
        self.assertFalse(a.approve_ready(lease,ready,os))
        self.assertIsNone(a.issue_worker_permit(lease,self.req,os,0,'xlsx'))
        self.assertIsNone(a.consume_worker_permit(permit,self.req,'/input/source.xlsx','/output/candidate.xlsx','openpyxl',0))
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
