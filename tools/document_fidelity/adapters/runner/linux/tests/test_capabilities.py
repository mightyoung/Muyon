"""Preflight and readonly-source regressions; all syscalls mocked, no process starts."""
import errno,os,unittest
from contextlib import ExitStack
from types import SimpleNamespace
from unittest.mock import patch
from tools.document_fidelity.adapters.runner.linux import capabilities,kernel

class CapabilityTests(unittest.TestCase):
    def fake(self,stack,*,pid_error=None,signal_error=None,seals=15):
        opened=stack.enter_context(patch.object(capabilities.os,'pidfd_open',return_value=71,side_effect=pid_error,create=True))
        signal=stack.enter_context(patch.object(capabilities.signal,'pidfd_send_signal',side_effect=signal_error,create=True))
        stack.enter_context(patch.object(capabilities.os,'memfd_create',return_value=72,create=True))
        stack.enter_context(patch.object(capabilities.os,'write',side_effect=lambda fd,data:len(data)))
        stack.enter_context(patch.object(capabilities.fcntl,'fcntl',side_effect=lambda fd,cmd,*args:seals if cmd==1034 else 0))
        closed=stack.enter_context(patch.object(capabilities.os,'close'))
        stack.enter_context(patch.object(capabilities.os,'supports_fd',{capabilities.os.execve}))
        return opened,signal,closed
    def test_missing_api_and_fd_exec_hold_before_any_ipc_or_popen(self):
        for name in ('pidfd_open','memfd_create'):
            with ExitStack() as stack:
                self.fake(stack)
                stack.enter_context(patch.object(capabilities.os,name,None))
                popen=stack.enter_context(patch.object(kernel.subprocess,'Popen'))
                pairs=stack.enter_context(patch.object(kernel.socket,'socketpair',side_effect=AssertionError('no IPC before preflight')))
                with self.assertRaisesRegex(ValueError,'runtime_capability'):
                    kernel.NativeLinuxSystem().launch(SimpleNamespace(job=b'job'))
                popen.assert_not_called();pairs.assert_not_called()
        with ExitStack() as stack:
            self.fake(stack);stack.enter_context(patch.object(capabilities.os,'supports_fd',set()))
            with self.assertRaisesRegex(ValueError,'runtime_capability'):capabilities.preflight()
    def test_kernel_enosys_and_signal_permission_failure_are_prelaunch_hold(self):
        for kwargs in ({'pid_error':OSError(errno.ENOSYS,'fake unavailable')},{'signal_error':PermissionError(errno.EPERM,'fake denied')}):
            with ExitStack() as stack:
                opened,signal,closed=self.fake(stack,**kwargs)
                popen=stack.enter_context(patch.object(kernel.subprocess,'Popen'))
                pairs=stack.enter_context(patch.object(kernel.socket,'socketpair',side_effect=AssertionError('no preflight')))
                with self.assertRaisesRegex(ValueError,'runtime_capability'):
                    kernel.NativeLinuxSystem().launch(SimpleNamespace(job=b'job'))
                popen.assert_not_called();pairs.assert_not_called()
    def test_success_probes_only_current_pid_signal_zero_and_sealed_memfd(self):
        with ExitStack() as stack:
            opened,signal,closed=self.fake(stack)
            capabilities.preflight()
            opened.assert_called_once_with(os.getpid());signal.assert_called_once_with(71,0)
            self.assertEqual({71,72},{call.args[0] for call in closed.call_args_list})
        with ExitStack() as stack:
            self.fake(stack,seals=0)
            with self.assertRaisesRegex(ValueError,'runtime_capability'):capabilities.preflight()
    def test_readonly_hash_rejects_writable_mount_even_when_bytes_match(self):
        info=SimpleNamespace(st_mode=0o100644,st_nlink=1,st_dev=1,st_ino=2,st_size=3,st_mtime_ns=4,st_ctime_ns=5)
        for flag,allowed in [(0,False),(os.ST_RDONLY,True)]:
            with patch.object(kernel.os,'fstat',return_value=info),patch.object(kernel.os,'fstatvfs',return_value=SimpleNamespace(f_flag=flag)),patch.object(kernel,'_proc',side_effect=lambda pid,name,*args:'mnt_id:\t41\n' if name.startswith('fdinfo/') else '41 1 0:1 / /bundle ro,nosuid - squashfs /dev/loop ro\n'),patch.object(kernel.os,'read',side_effect=[b'abc',b'']):
                if allowed:self.assertEqual(kernel.model.sha(b'abc'),kernel._regular_hash(8))
                else:
                    with self.assertRaises(ValueError):kernel._regular_hash(8)

    def test_root_ro_cannot_hide_writable_nested_mount_or_readonly_bind(self):
        info=SimpleNamespace(st_mode=0o100400,st_nlink=1,st_dev=1,st_ino=2,st_size=3,st_mtime_ns=4,st_ctime_ns=5)
        for nested in ('42 41 0:1 / /bundle/lib rw - ext4 /dev/sda rw', '42 41 0:1 / /bundle/lib ro - ext4 /dev/sda rw'):
            table='41 1 0:1 / /bundle ro - squashfs /dev/loop ro\n'+nested+'\n'
            with patch.object(kernel.os,'fstat',return_value=info),patch.object(kernel.os,'fstatvfs',return_value=SimpleNamespace(f_flag=os.ST_RDONLY)),patch.object(kernel,'_proc',side_effect=lambda pid,name,*args:'mnt_id:\t42\n' if name.startswith('fdinfo/') else table),patch.object(kernel.os,'read',side_effect=[b'abc',b'']):
                with self.assertRaises(ValueError):kernel._regular_hash(8)

    def test_preexec_python_maps_never_substitute_for_postexec_bwrap_maps(self):
        from tools.document_fidelity.adapters.runner.linux.layout import SANDBOX_CODE
        for bad_library in (True,False):
            with self.subTest(bad_library=bad_library),ExitStack() as stack:
                native=kernel.NativeLinuxSystem();native.baseline_filters=0
                native.config=SimpleNamespace(policy=SimpleNamespace(),bwrap_sha256='b'*64,image_manifest=(('runtime/python3','a'*64),),domain_identity=(1,2))
                state=SimpleNamespace(sandbox_pid=72,sandbox_pidfd=92,sandbox_start=456,process=SimpleNamespace(pid=71),pidfd=91,starttime=123,spec={'format':'xlsx'},child_socket_inode=99,image_fd=42,output_fd=43,source=b'source',job=b'job')
                phase=['python'];seen=[]
                def maps(pid,sandbox):
                    seen.append((pid,phase[0]))
                    if pid==71 and phase[0]=='bwrap' and bad_library:raise ValueError('unreviewed_postexec_bwrap_library')
                    return [('fake-reviewed-map',)]
                stack.enter_context(patch.object(native,'_check_maps',side_effect=maps))
                native._check_maps(71,False) # old launch observation of Python
                phase[0]='bwrap'
                stack.enter_context(patch.object(native,'_alive',return_value=True));stack.enter_context(patch.object(native,'_members',return_value={71,72}))
                stack.enter_context(patch.object(native,'_verify_executable',return_value='b'*64))
                stack.enter_context(patch.object(kernel,'_starttime',side_effect=lambda pid:123 if pid==71 else 456))
                status='NoNewPrivs: 1\nSeccomp: 2\nSeccomp_filters: 1\nCapEff: 0\nCapPrm: 0\nCapInh: 0\nCapAmb: 0\n'
                def proc(pid,name,*args):
                    return {'environ':'','status':status,'limits':'fake','cmdline':'\x00'.join(['/runtime/python3','-I','-S','-B','-c',SANDBOX_CODE,'' ]),'mountinfo':'fake','net/dev':'lo: 0','net/route':'header','net/ipv6_route':''}[name]
                stack.enter_context(patch.object(kernel,'_proc',side_effect=proc));stack.enter_context(patch.object(kernel,'_limits'));stack.enter_context(patch.object(kernel,'_mounts'))
                def link(path):
                    if path.endswith('/fd/3'):return 'socket:[99]'
                    if path.endswith('/ns/time'):return 'same-time'
                    return 'host-ns' if '/self/' in path else 'private-ns'
                stack.enter_context(patch.object(kernel.os,'readlink',side_effect=link));stack.enter_context(patch.object(kernel.os,'listdir',return_value=['0','1','2','3']))
                stack.enter_context(patch.object(kernel.os,'open',return_value=200));stack.enter_context(patch.object(kernel.os,'close'))
                stack.enter_context(patch.object(kernel,'_beneath',side_effect=lambda fd,name,*args:201 if name.startswith('input/') else 202 if name.startswith('job/') else 203))
                stack.enter_context(patch.object(kernel,'_read',side_effect=lambda fd,*args:b'source' if fd==201 else b'job'))
                stack.enter_context(patch.object(kernel.os,'fstat',side_effect=lambda fd:SimpleNamespace(st_dev=2 if fd in (203,43) else 1,st_ino=2 if fd in (203,43) else 1)))
                if bad_library:
                    with self.assertRaisesRegex(ValueError,'postexec_bwrap_library'):native._observe(state)
                else:
                    result=native._observe(state);self.assertEqual('b'*64,result['root']['executable'])
                self.assertIn((71,'bwrap'),seen)
