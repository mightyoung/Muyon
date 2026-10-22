"""Read-only cgroup observation with every syscall faked. Never signals/kills."""
import stat,unittest
from contextlib import ExitStack
from types import SimpleNamespace as NS
from unittest.mock import patch
from tools.document_fidelity.adapters.runner.linux import kernel
from tools.document_fidelity.adapters.runner import model

class DomainTests(unittest.TestCase):
    def fake(self,stack,*,members='',populated='0',descendants='0',child=False):
        native=kernel.NativeLinuxSystem();native.domain_fd=44
        values={'cgroup.procs':members,'cgroup.events':'populated '+populated+'\nfrozen 0','cgroup.max.descendants':descendants}
        stack.enter_context(patch.object(kernel,'_text_at',side_effect=lambda fd,name,*args:values[name]))
        stack.enter_context(patch.object(kernel.os,'listdir',return_value=['cgroup.events','cgroup.procs','cgroup.max.descendants']+(['D'] if child else [])))
        stack.enter_context(patch.object(kernel.os,'stat',side_effect=lambda name,**kw:NS(st_mode=stat.S_IFDIR if name=='D' else stat.S_IFREG,st_dev=1,st_ino=2)))
        return native
    def test_root_empty_cannot_hide_recursive_populated_or_existing_child(self):
        for kwargs in ({'populated':'1'},{'child':True},{'descendants':'max'},{'descendants':'1'}):
            with self.subTest(kwargs=kwargs),ExitStack() as stack:
                native=self.fake(stack,**kwargs)
                with self.assertRaises(ValueError):native._members()
    def test_leaf_members_and_recursive_empty_are_both_observed(self):
        with ExitStack() as stack:
            native=self.fake(stack);self.assertEqual(set(),native._members());self.assertTrue(callable(getattr(native,'_domain_empty',None)));self.assertTrue(native._domain_empty())
        with ExitStack() as stack:
            native=self.fake(stack,members='71 72',populated='1')
            self.assertEqual({71,72},native._members());self.assertFalse(native._domain_empty())
    def test_recursive_kill_refuses_child_domain_before_open_or_write(self):
        with ExitStack() as stack:
            native=self.fake(stack,child=True)
            opened=stack.enter_context(patch.object(kernel,'_beneath'));written=stack.enter_context(patch.object(kernel.os,'write'));stack.enter_context(patch.object(kernel.os,'close'))
            with self.assertRaises(ValueError):native.kill(NS(process=None))
            opened.assert_not_called();written.assert_not_called()
    def test_reap_capture_cleanup_reject_root_empty_but_recursive_live(self):
        for operation in ('reap','capture','cleanup'):
            with self.subTest(operation=operation),ExitStack() as stack:
                native=self.fake(stack,populated='1')
                state=NS(uncertain=False,process=NS(pid=71,poll=lambda:0),reaped=operation!='reap',output_fd=9,input_fd=10,job_dir_fd=11,spec={'format':'xlsx'},root='/fake',root_identity=(1,2))
                stack.enter_context(patch.object(native,'_close',side_effect=AssertionError('must not close/delete')))
                stack.enter_context(patch.object(kernel,'_proc',return_value=''))
                stack.enter_context(patch.object(kernel.snapshot,'capture',side_effect=AssertionError('must not snapshot')))
                stack.enter_context(patch.object(kernel.shutil,'rmtree',side_effect=AssertionError('must not delete')))
                with self.assertRaises(ValueError):
                    if operation=='reap':native.reap(state,0)
                    elif operation=='capture':native.capture(state,model.Policy())
                    else:native.cleanup(state)
                if operation=='reap':self.assertFalse(state.reaped)
