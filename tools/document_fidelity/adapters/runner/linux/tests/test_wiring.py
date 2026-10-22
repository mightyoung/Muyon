"""Import/source logic, fake syscalls and socketpairs only; native paths NOT_RUN."""
import importlib,os,socket,sys,time,unittest
from dataclasses import asdict
from types import SimpleNamespace
from unittest.mock import patch
from tools.document_fidelity.adapters.runner import authority,model
from tools.document_fidelity.adapters.runner.tests import test_launcher as previous
from tools.document_fidelity.adapters.runner.linux import ipc,kernel,seccomp

class WiringTests(unittest.TestCase):
    def test_all_native_source_modules_import_without_engine_or_os_effects(self):
        for name in ('bootstrap','host_stage','worker_permit','session','backend'):
            importlib.import_module('tools.document_fidelity.adapters.runner.linux.'+name)
        self.assertFalse(any(name in sys.modules for name in ('openpyxl','docx','pptx')))
    def test_socketpair_worker_grant_one_use_and_authenticated_entry_only(self):
        from tools.document_fidelity.adapters.runner.linux.worker_permit import receive_permit,RemoteWorkerPermit
        f=previous.LauncherTests();f.setUp()
        a,b=socket.socketpair();self.addCleanup(a.close);self.addCleanup(b.close)
        host=ipc.Channel(a,'test_attempt',model.digest(f.req),expected_pid=os.getpid(),expected_uid=os.getuid())
        child=ipc.Channel(b,'test_attempt',model.digest(f.req),expected_pid=os.getpid(),expected_uid=os.getuid())
        binding=authority.bind(f.req,'test_attempt')
        host.send('release',dict(engine=asdict(f.engine),policy=asdict(f.policy),binding=asdict(binding),expires_ms=time.monotonic()*1000+1000),100)
        permit=receive_permit(child,f.req)
        self.assertEqual(f.engine,permit.consume(f.req,'/input/source.xlsx','/output/candidate.xlsx','openpyxl')[0])
        with self.assertRaises(ValueError):permit.consume(f.req,'/input/source.xlsx','/output/candidate.xlsx','openpyxl')
        # Explicit synthetic notification; no library was imported or executed.
        permit.engine_entered();frame=host.receive(100);self.assertEqual('entry',frame.kind)
        with self.assertRaises(ValueError):permit.engine_entered()
        with self.assertRaises(TypeError):RemoteWorkerPermit(None,f.req,{},child)
    def test_seccomp_program_is_data_only_and_wrong_arch_and_x32_are_killed(self):
        program=seccomp.program();self.assertEqual((0x20,0,0,4),program[0])
        self.assertIn((0x06,0,0,0x80000000),program)
        self.assertTrue({41,42,53,56,57,58,59,322,435}.issubset(seccomp.DENIED))
    def test_native_poll_drains_logs_before_exit_and_counts_trailing_overflow(self):
        # All OS reads/select/process observations replaced by fake syscalls.
        class Stream:
            def __init__(self,n):self.n=n
            def fileno(self):return self.n
        stdout,stderr=Stream(10),Stream(11)
        state=SimpleNamespace(process=SimpleNamespace(stdout=stdout,stderr=stderr,poll=lambda:0),sandbox=SimpleNamespace(socket=object()),entry=('synthetic',),log_eof=set(),log_bytes={'stdout':0,'stderr':0})
        native=kernel.NativeLinuxSystem();native.config=SimpleNamespace(policy=model.Policy(max_stdout_bytes=16,max_stderr_bytes=16))
        chunks={10:iter([b'a'*9,b'a'*9]),11:iter([b''])}
        with patch.object(kernel.select,'select',return_value=([stdout,stderr],[],[])),patch.object(kernel.os,'read',side_effect=lambda fd,n:next(chunks[fd])):
            self.assertEqual('stdout',native.poll(state,10).kind)
            with self.assertRaises(ValueError):native.poll(state,10)
        self.assertEqual(18,state.log_bytes['stdout'])
    def test_bwrap_profile_disables_site_and_only_preserves_fixed_fds(self):
        from tools.document_fidelity.adapters.runner.linux.host_stage import bwrap_argv
        argv=bwrap_argv({'bwrap':'/pinned/bwrap','spec':{'format':'xlsx'}})
        self.assertIn('-S',argv);self.assertIn('--unshare-all',argv)
        self.assertEqual('6',argv[argv.index('--preserve-fds')+1])
        self.assertNotIn('/workspace',argv);self.assertNotIn('--share-net',argv)
    def test_default_provider_and_plain_json_do_not_touch_native_system(self):
        from tools.document_fidelity.adapters.runner.linux.provider import provision
        with patch.object(kernel.NativeLinuxSystem,'qualify',side_effect=AssertionError('native qualification must not run')):
            self.assertEqual('held',provision().status)
            self.assertEqual('held',provision({'verified':True},{'scope':True}).status)
    def test_dispatch_consumes_original_authority_under_its_lock_once(self):
        f=previous.LauncherTests();f.setUp();osfake=previous.FakeHostOS();a=authority.Authority.host(f.engine,f.policy,previous.FakeHostSession())
        lease=a.admit(f.req,model.sha(f.source),osfake,'dispatch_test',0);a.claim(lease,f.req,osfake,0)
        ready=model.SandboxReady(a.binding(lease),f.engine,f.policy.digest(),True,True,True,True,True,True)
        self.assertTrue(a.approve_ready(lease,ready,osfake));seen=[]
        def release(engine,policy,binding,expiry):seen.append((a._lock._is_owned(),binding,expiry))
        self.assertTrue(a.dispatch_worker(lease,f.req,osfake,0,'xlsx',release))
        self.assertTrue(seen[0][0]);self.assertEqual(a.binding(lease),seen[0][1])
        self.assertFalse(a.dispatch_worker(lease,f.req,osfake,0,'xlsx',release));self.assertEqual(1,len(seen))
    def test_signal_pins_root_pidfd_and_rechecks_descendant_membership(self):
        native=kernel.NativeLinuxSystem();state=SimpleNamespace(pidfd=9,process=SimpleNamespace(pid=10))
        calls=[];members=iter([{20},set()])
        with patch.object(native,'_members',side_effect=lambda:next(members)),patch.object(native,'_alive',return_value=True),patch.object(kernel,'_starttime',return_value=123),patch.object(kernel.os,'pidfd_open',return_value=99,create=True),patch.object(kernel.os,'close'),patch('signal.pidfd_send_signal',side_effect=lambda fd,sig:calls.append((fd,sig)),create=True):
            with self.assertRaises(ValueError):native.terminate(state)
        self.assertEqual([(9,15)],calls) # never signal descendant whose domain changed
    def test_actual_send_loop_handles_partial_writes_on_socketpair(self):
        class ShortSend:
            def __init__(self,sock):self.sock=sock
            def __getattr__(self,name):return getattr(self.sock,name)
            def send(self,data):return self.sock.send(data[:3])
        a,b=socket.socketpair();self.addCleanup(a.close);self.addCleanup(b.close)
        host=ipc.Channel(ShortSend(a),'short','a'*64,expected_pid=os.getpid(),expected_uid=os.getuid())
        child=ipc.Channel(b,'short','a'*64,expected_pid=os.getpid(),expected_uid=os.getuid())
        host.send('paused',{},100);self.assertEqual('paused',child.receive(100).kind)
