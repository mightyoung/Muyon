"""Source-bound temp-evidence classifier controls, never actual Rust RED."""
from pathlib import Path
import copy
import hashlib
import tempfile
import unittest
from host_checkpoint import TEMP_CONTRACT, inventory, temp_red
from test_workflow_selection import select


def transcript():
    red=TEMP_CONTRACT['red'];target=red['target'];name=red['test']
    passed=[n for n in TEMP_CONTRACT['targets'][target]['names'] if n!=name]
    return (f'Finished `release` profile [optimized]\nRunning tests/{target}.rs (target/release/deps/{target}-abc)\n'
        +'\n'.join(f'test {n} ... ok' for n in passed)+'\n'
        +f"thread '{name}' (14) panicked at tests/service_lifecycle.rs:422:9:\n"
        +red['rust_assert']+f'\ntest {name} ... FAILED\n'
        +'test result: FAILED. 3 passed; 1 failed; 0 ignored; 0 measured; 0 filtered out;\n')


class ServiceTempRedControls(unittest.TestCase):
    def test_requires_three_healthy_cases_and_only_precise_new_failure(self):
        raw=transcript();red=TEMP_CONTRACT['red']
        for sibling in [raw,raw.replace("' (14) panicked", "' panicked")]:
            self.assertTrue(temp_red(sibling,101)['accepted'])
        for bad in [raw+raw,raw.replace(red['rust_assert'],'different initialization failure'),
                    raw.replace('3 passed','2 passed'),raw.replace('0 filtered','1 filtered'),
                    raw.replace('0 ignored','1 ignored'),raw.replace('0 measured','1 measured'),
                    raw.replace('Finished','Compiling'),raw.replace(red['test'],'unexpected_test'),
                    raw+'thread \'worker\' (15) panicked at tests/setup.rs:1:1:\n\n',
                    raw+'thread \'worker\' panicked at tests/setup.rs:1:1:\nauxiliary\n']:
            self.assertFalse(temp_red(bad,101)['accepted'])
        for name in TEMP_CONTRACT['targets']['service_lifecycle']['names'][:-1]:
            self.assertFalse(temp_red(raw.replace('test '+name+' ... ok',''),101)['accepted'])
        for status in [0,1,124,-6,-9]:
            self.assertFalse(temp_red(raw,status)['accepted'])
        self.assertEqual(temp_red(raw,101)['post_assertion_bytes'],'NOT_RUN')

    def test_lifecycle_phase_requires_all_42_prior_passes_and_keeps_101(self):
        import contextlib
        import io
        from unittest.mock import patch
        import linux_gate
        from test_service_host_green import transcript as positive_transcript
        expected=[n for n in TEMP_CONTRACT['targets'] if n!='service_lifecycle']
        for failed in [None,'service_root']:
            with tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp);evidence=root/'evidence';evidence.mkdir();work=root/'work';work.mkdir()
                host=root/TEMP_CONTRACT['manifest'];host.parent.mkdir(parents=True)
                (host.parent/'Cargo.lock').write_text('control lock');targets=[]
                def fake_run(command,log,env,**kwargs):
                    words=[str(v) for v in command];raw='';status=0
                    if words==['rustc','--version']:
                        raw='rustc 1.99.0 (helper control)\n'
                    elif '--bin' in words:
                        binary=work/'host-target/release/muyon-plugin-contract-lab';binary.parent.mkdir(parents=True);binary.write_bytes(b'control binary')
                    elif '--test' in words:
                        target=words[words.index('--test')+1];targets.append(target)
                        raw=transcript() if target=='service_lifecycle' else positive_transcript(target)
                        if target=='service_lifecycle':status=101
                        if target==failed:raw=raw.replace(' ... ok',' ... FAILED',1);status=101
                    log.write_text(raw);return status
                with patch.object(linux_gate,'ROOT',root),patch.object(linux_gate,'checkpoint_inventory',return_value=TEMP_CONTRACT) as checked,patch.object(linux_gate,'run',side_effect=fake_run),contextlib.redirect_stdout(io.StringIO()):
                    result=linux_gate.host_checkpoint(evidence,work,'a'*40,temp=True)
                checked.assert_called_once_with(root,temp=True)
                self.assertEqual(targets,expected+(['service_lifecycle'] if failed is None else []))
                self.assertEqual(result['accepted'],failed is None)
                self.assertFalse(result['shipping_or_service_green'])
                self.assertEqual(result['not_run']['temp_evidence_byte_preservation_tail'],'NOT_RUN')
                if failed is None:
                    self.assertEqual(result['command_exit_code'],101)
                    self.assertEqual(result['classification'],'semantic_red')
                    self.assertEqual(result['executed_tests'],46)
                else:
                    self.assertEqual(result['temp_red']['classification'],'NOT_RUN')
                    self.assertEqual(result['executed_tests'],42)

    def test_temp_source_has_separate_46_inventory_and_mode(self):
        self.assertEqual(sum(len(g['names']) for g in TEMP_CONTRACT['targets'].values()),46)
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);c=copy.deepcopy(TEMP_CONTRACT)
            for group in c['targets'].values():
                data='\n'.join('#[test]\nfn '+n+'() {}' for n in group['names']).encode()
                p=root/group['path'];p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
                group['sha256']=hashlib.sha256(data).hexdigest()
                group['blob_sha']=hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()
            self.assertEqual(inventory(root,c,temp=True),c)
            lifecycle=root/c['targets']['service_lifecycle']['path'];lifecycle.write_bytes(lifecycle.read_bytes()+b'\n')
            with self.assertRaisesRegex(RuntimeError,'host_checkpoint_inventory_invalid'):
                inventory(root,c,temp=True)
        for suite,ref in [('service-temp-red','ignored'),('', 'lab/android-rust-bridge-service-temp-red-20261015')]:
            result,output=select(suite,ref)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertEqual(output,{'mode':'service-temp-red','red':'[]'})


if __name__=='__main__':
    unittest.main()
