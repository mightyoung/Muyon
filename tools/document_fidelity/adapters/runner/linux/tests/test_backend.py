"""Fake kernel/process/domain only. No NativeLinuxSystem call is executed."""
import unittest
from dataclasses import replace
from tools.document_fidelity.adapters.runner import authority,launcher,model
from tools.document_fidelity.adapters.runner.tests import test_launcher as previous
from tools.document_fidelity.adapters.runner.linux import backend,kernel,session

class FakeNative:
    def __init__(self,mode='ok'):self.mode=mode;self.calls=[];self.logs=[];self.tick=0;self.exists=False;self.reaped=False
    def now_ms(self):return self.tick
    def qualify(self,config):self.calls.append('qualify');return 'FAKE_NOT_PRODUCTION'
    def stage(self,attempt,spec,source,job,register):
        self.calls.append('stage');self.exists=True
        state={'attempt':attempt,'source':source,'job':job,'output':b'abc'};register(state);return state
    def launch(self,state):
        self.calls.append('launch')
        if self.mode=='launch_uncertain':raise RuntimeError('fake uncertain launch')
        return 'owned-paused-supervisor'
    def observe_ready(self,state,binding,engine,policy):
        self.calls.append('observe')
        if self.mode=='ready_denied':raise ValueError('fake namespace insufficient')
        return 'FAKE_KERNEL_OBSERVATION'
    def release(self,state,grant):self.calls.append('release')
    def poll(self,state,wait):
        self.calls.append('poll');self.tick+=wait
        if self.logs:return self.logs.pop(0)
        return model.Event('exit',exit_code=0)
    def measure(self,state):return model.OutputState(3,False)
    def terminate(self,state):self.calls.append('terminate')
    def kill(self,state):self.calls.append('kill')
    def reap(self,state,wait):self.calls.append('reap');self.reaped=self.mode!='unreaped';return self.reaped
    def capture(self,state,policy):
        self.calls.append('capture')
        if not self.reaped:raise ValueError('not_reaped')
        return model.Snapshot(state['output'],state['source'],state['job'],True,1,False)
    def cleanup(self,state):
        if not self.reaped:raise ValueError('not_reaped')
        self.calls.append('cleanup')
    def quarantine(self,state):self.calls.append('quarantine')

class BackendTests(unittest.TestCase):
    def setUp(self):
        f=previous.LauncherTests();f.setUp();self.f=f
    def test_concrete_backend_default_hold_before_process_and_fake_never_qualifies(self):
        b=backend.LinuxBackend();self.assertFalse(b.__class__.__abstractmethods__)
        with self.assertRaises(backend.Hold):b.reserve('attempt',{},b'',b'')
        fake=FakeNative();b=backend.LinuxBackend(config=object(),system=fake)
        s=session.LinuxHostSession(b,None)
        self.assertFalse(s.verify_executor(b));self.assertFalse(fake.calls)
    def test_pre_spawn_supervisor_owned_reconciled_and_reaped_on_ready_failure(self):
        fake=FakeNative('ready_denied');b=backend.LinuxBackend(config=object(),system=fake)
        # Explicit fake verifier permits observing lifecycle source only; it is
        # not LinuxHostSession qualification or a genuine host credential.
        class FakeVerifier(previous.FakeHostSession):
            def verify_executor(s,executor):return executor is b
        a=authority.Authority.host(self.f.engine,self.f.policy,FakeVerifier())
        r=launcher.run_production(self.f.source,self.f.req,launcher.TrustedRuntimeBinding(a,b))
        self.assertEqual('failed',r.public['status'],r.public)
        self.assertIn('terminate',fake.calls);self.assertIn('reap',fake.calls);self.assertIn('cleanup',fake.calls)
        self.assertNotIn('release',fake.calls)
    def test_reserve_uncertain_launch_has_attempt_ownership_and_no_retry(self):
        fake=FakeNative('launch_uncertain');b=backend.LinuxBackend(config=object(),system=fake)
        with self.assertRaises(RuntimeError):b.reserve('attempt_1',{'format':'xlsx'},b'input',b'job')
        state=b.reconcile('attempt_1');self.assertTrue(state.known);self.assertIsNotNone(state.workspace);self.assertIsNotNone(state.process)
        self.assertEqual(1,fake.calls.count('launch'))
        with self.assertRaises(backend.Hold):b.reserve('attempt_1',{},b'',b'')
    def test_snapshot_and_cleanup_cannot_precede_tree_reap(self):
        fake=FakeNative();b=backend.LinuxBackend(config=object(),system=fake)
        state=b.reserve('attempt_1',{'format':'xlsx'},b'input',b'job')
        with self.assertRaises(backend.Hold):b.snapshot(state,self.f.policy)
        with self.assertRaises(backend.Hold):b.cleanup(state)
        self.assertTrue(b.reap_tree(state,5));self.assertEqual(b'abc',b.snapshot(state,self.f.policy).candidate)
        b.cleanup(state)
    def test_full_fake_backend_release_and_normal_candidate_validation(self):
        from tools.document_fidelity.tests.test_adapter import edit_bytes
        class ValidFake(FakeNative):
            def stage(native,*args):
                state=super().stage(*args);state['output']=edit_bytes(state['source']);return state
            def measure(native,state):return model.OutputState(len(state['output']),False)
        fake=ValidFake();b=backend.LinuxBackend(config=object(),system=fake)
        class FakeVerifier(previous.FakeHostSession):
            def verify_executor(s,executor):return executor is b
        a=authority.Authority.host(self.f.engine,self.f.policy,FakeVerifier())
        r=launcher.run_production(self.f.source,self.f.req,launcher.TrustedRuntimeBinding(a,b))
        self.assertEqual('candidate_validated',r.public['status'],r.public)
        self.assertEqual(1,fake.calls.count('release'));self.assertIn('reap',fake.calls);self.assertIn('capture',fake.calls)
        self.assertFalse(session.LinuxHostSession(b,None).verify_executor(b))
    def test_pre_spawn_unreaped_supervisor_is_quarantined_not_cleaned(self):
        class DeniedUnreaped(FakeNative):
            def observe_ready(native,*args):raise ValueError('fake insufficient kernel observation')
        fake=DeniedUnreaped('unreaped');b=backend.LinuxBackend(config=object(),system=fake)
        class FakeVerifier(previous.FakeHostSession):
            def verify_executor(s,executor):return executor is b
        a=authority.Authority.host(self.f.engine,self.f.policy,FakeVerifier())
        r=launcher.run_production(self.f.source,self.f.req,launcher.TrustedRuntimeBinding(a,b))
        self.assertEqual('outcome_unknown',r.public['status']);self.assertIn('kill',fake.calls)
        self.assertIn('quarantine',fake.calls);self.assertNotIn('cleanup',fake.calls);self.assertNotIn('release',fake.calls)
    def test_kernel_text_parsers_reject_false_isolation_and_unlimited_limits(self):
        with self.assertRaises(ValueError):kernel.parse_status('NoNewPrivs:\t0\nCapEff:\t0\nSeccomp:\t2\n')
        self.assertEqual(1,kernel.parse_status('NoNewPrivs:\t1\nCapEff:\t0000\nCapPrm:\t0000\nCapInh:\t0000\nCapAmb:\t0000\nSeccomp:\t2\nSeccomp_filters:\t2\n')['NoNewPrivs'])
        for text in ('memory.max max\npids.max 8','memory.max 1024\npids.max max'):
            with self.assertRaises(ValueError):kernel.check_domain_values(dict(line.split() for line in text.splitlines()),self.f.policy)
    def test_sanitized_environment_is_observed_not_inferred_from_argv(self):
        self.assertEqual({'LC_CTYPE':'C.UTF-8'},kernel.check_environment(b'LC_CTYPE=C.UTF-8\0'))
        for data in (b'AWS_TOKEN=secret\0',b'HOME=/home/user\0',b'PYTHONPATH=/host\0',b'LC_CTYPE=C.UTF-8\0LC_CTYPE=C\0'):
            with self.assertRaises(ValueError):kernel.check_environment(data)
    def test_same_lock_dispatch_cannot_serialize_or_replay_capability(self):
        a=authority.Authority.simulation(self.f.engine,self.f.policy)
        self.assertTrue(callable(getattr(a,'dispatch_worker',None)))
        self.assertFalse(a.dispatch_worker(None,self.f.req,None,0,'xlsx',lambda *_:self.fail('fake must not release')))
