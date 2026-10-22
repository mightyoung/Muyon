"""Safe local staging files and fake cgroup syscalls; no native launch/qualification."""
import os,tempfile,unittest
from pathlib import Path
from types import SimpleNamespace as NS
from unittest.mock import patch
from tools.document_fidelity.adapters.runner.linux import backend,kernel
from tools.document_fidelity.adapters.runner.tests import test_launcher as previous

class OwnershipTests(unittest.TestCase):
    def test_source_written_open_failure_and_failed_rmtree_retain_owned_staging(self):
        f=previous.LauncherTests();f.setUp()
        with tempfile.TemporaryDirectory() as directory:
            native=kernel.NativeLinuxSystem();native.qualified=True
            native.config=NS(workspace_parent=Path(directory),engine=f.engine,policy=f.policy)
            b=backend.LinuxBackend(config=object(),system=native);b.qualification='FAKE_NOT_PRODUCTION'
            real_open=os.open
            def opened(path,*args,**kwargs):
                if Path(path).name=='request.json':raise OSError('fake job open failure after source write')
                return real_open(path,*args,**kwargs)
            with patch.object(kernel.os,'open',side_effect=opened),patch.object(kernel.shutil,'rmtree',side_effect=OSError('fake rmtree denied')),patch.object(kernel.subprocess,'Popen') as popen:
                with self.assertRaises(OSError):b.reserve('attempt',{'format':'xlsx'},b'original',b'job')
                result=b.reconcile('attempt')
                self.assertFalse(result.known,'failed staging cleanup must never become known-empty')
                self.assertIsNotNone(result.workspace)
                state=result.workspace.native
                self.assertEqual(b'original',(state.root/'input/source.xlsx').read_bytes())
                self.assertTrue(state.cleanup_failed)
                b.quarantine('attempt',result.workspace)
                self.assertTrue(state.quarantined)
                popen.assert_not_called()
    def test_successful_early_staging_discard_has_record_and_no_process(self):
        f=previous.LauncherTests();f.setUp()
        with tempfile.TemporaryDirectory() as directory:
            native=kernel.NativeLinuxSystem();native.qualified=True
            native.config=NS(workspace_parent=Path(directory),engine=f.engine,policy=f.policy)
            b=backend.LinuxBackend(config=object(),system=native);b.qualification='FAKE_NOT_PRODUCTION'
            real_open=os.open
            def opened(path,*args,**kwargs):
                if Path(path).name=='request.json':raise OSError('fake write failure')
                return real_open(path,*args,**kwargs)
            with patch.object(kernel.os,'open',side_effect=opened),patch.object(kernel.subprocess,'Popen') as popen:
                with self.assertRaises(OSError):b.reserve('attempt',{'format':'xlsx'},b'original',b'job')
                self.assertIsNotNone(b.attempt.native,'record must precede staging effects')
                self.assertTrue(b.attempt.native.stage_discarded)
                self.assertTrue(b.reconcile('attempt').known)
                self.assertIsNone(b.reconcile('attempt').workspace)
                self.assertEqual([],os.listdir(directory));popen.assert_not_called()

    def test_mkdir_uncertainty_retains_registered_path_without_deletion(self):
        with tempfile.TemporaryDirectory() as directory:
            native=kernel.NativeLinuxSystem();native.qualified=True
            native.config=NS(workspace_parent=Path(directory))
            records=[];real_mkdir=os.mkdir
            def mkdir(path,mode):
                self.assertEqual(1,len(records),'ownership before first side effect')
                real_mkdir(path,mode);raise OSError('fake uncertain mkdir')
            with patch.object(kernel.os,'mkdir',side_effect=mkdir),patch.object(kernel.shutil,'rmtree') as removed:
                with self.assertRaises(OSError):native.stage('attempt',{},b'',b'',records.append)
                self.assertTrue(records[0].cleanup_failed)
                self.assertFalse(records[0].stage_discarded)
                self.assertTrue(records[0].root.is_dir());removed.assert_not_called()
    def test_failed_close_is_retained_and_never_retried_by_cleanup(self):
        f=previous.LauncherTests();f.setUp()
        with tempfile.TemporaryDirectory() as directory:
            native=kernel.NativeLinuxSystem();native.qualified=True
            native.config=NS(workspace_parent=Path(directory),engine=f.engine,policy=f.policy)
            records=[];real_close=os.close;closes=[]
            def closed(fd):
                closes.append(fd);real_close(fd);raise OSError('fake ambiguous close after release')
            with patch.object(kernel.os,'close',side_effect=closed),patch.object(kernel.shutil,'rmtree') as removed:
                with self.assertRaises(OSError):native.stage('attempt',{'format':'xlsx'},b'original',b'job',records.append)
                state=records[0];self.assertTrue(state.cleanup_failed)
                self.assertEqual(1,len(closes));self.assertEqual(set(closes),state.uncertain_fds)
                self.assertTrue((state.root/'input/source.xlsx').exists());removed.assert_not_called()
