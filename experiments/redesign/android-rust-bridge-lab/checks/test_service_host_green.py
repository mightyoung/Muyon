"""Source inventory and strict host GREEN controls; not real Rust execution."""
import copy
import hashlib
from pathlib import Path
import tempfile
import unittest
from host_checkpoint import GREEN_CONTRACT, inventory, target_green
from test_workflow_selection import select


def transcript(target):
    names=GREEN_CONTRACT['targets'][target]['names']
    return ('Finished `release` profile [optimized]\n'
        + f'Running tests/{target}.rs (target/release/deps/{target}-abc)\n'
        + '\n'.join(f'test {name} ... ok' for name in names)
        + f'\ntest result: ok. {len(names)} passed; 0 failed; 0 ignored; 0 measured; 0 filtered out;\n')


class ServiceHostGreenControls(unittest.TestCase):
    def test_all_seven_targets_require_exact_complete_pass(self):
        self.assertEqual({k:len(v['names']) for k,v in GREEN_CONTRACT['targets'].items()},
            dict(native_read=25,contract_transport=8,service_runtime=2,service_root=2,
                 service_controller=4,service_oracle=1,service_lifecycle=3))
        for target,group in GREEN_CONTRACT['targets'].items():
            raw=transcript(target)
            self.assertTrue(target_green(target,raw,0,service=True)['accepted'])
            for bad in [raw+raw,raw.replace(group['names'][0],'unknown_name'),
                        raw.replace(' ... ok',' ... FAILED',1),raw.replace('0 ignored','1 ignored'),
                        raw.replace('0 filtered','1 filtered'),raw.replace('0 measured','1 measured'),
                        raw.replace('Finished','Compiling'),raw+"\nthread 'worker' panicked at tests/setup.rs:1:1:\n\n"]:
                self.assertFalse(target_green(target,bad,0,service=True)['accepted'])
            for status in [1,101,124,-6,-9]:
                self.assertFalse(target_green(target,raw,status,service=True)['accepted'])
        self.assertFalse(target_green('unknown',transcript('service_oracle'),0,service=True)['accepted'])

    def test_closed_source_inventory_and_changed_oracle_hash(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);contract=copy.deepcopy(GREEN_CONTRACT)
            for group in contract['targets'].values():
                data='\n'.join('#[test]\nfn '+name+'() {}' for name in group['names']).encode()
                path=root/group['path'];path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
                group['sha256']=hashlib.sha256(data).hexdigest()
                group['blob_sha']=hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()
            self.assertEqual(inventory(root,contract,service=True),contract)
            oracle=root/contract['targets']['service_oracle']['path'];before=oracle.read_bytes();oracle.write_bytes(before+b'\n')
            with self.assertRaisesRegex(RuntimeError,'host_checkpoint_inventory_invalid'):
                inventory(root,contract,service=True)
            oracle.write_bytes(before)
            extra=oracle.parent/'unexpected.rs';extra.write_text('#[test]\nfn unexpected() {}')
            with self.assertRaisesRegex(RuntimeError,'host_checkpoint_inventory_invalid'):
                inventory(root,contract,service=True)

    def test_orchestration_runs_all_45_and_keeps_service_acceptance_separate(self):
        import contextlib
        import io
        from unittest.mock import patch
        import linux_gate
        for failing in [None, 'service_oracle']:
            with tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp);evidence=root/'evidence';evidence.mkdir();work=root/'work';work.mkdir()
                host=root/GREEN_CONTRACT['manifest'];host.parent.mkdir(parents=True)
                (host.parent/'Cargo.lock').write_text('control lock')
                targets=[]
                def fake_run(command,log,env,**kwargs):
                    words=[str(v) for v in command];raw='';status=0
                    if words==['rustc','--version']:
                        raw='rustc 1.99.0 (helper control)\n'
                    elif '--bin' in words:
                        binary=work/'host-target/release/muyon-plugin-contract-lab';binary.parent.mkdir(parents=True);binary.write_bytes(b'control binary')
                    elif '--test' in words:
                        target=words[words.index('--test')+1];targets.append(target);raw=transcript(target)
                        if target==failing:
                            raw=raw.replace(' ... ok',' ... FAILED',1);status=101
                    log.write_text(raw);return status
                with patch.object(linux_gate,'ROOT',root), patch.object(linux_gate,'checkpoint_inventory',return_value=GREEN_CONTRACT) as checked, patch.object(linux_gate,'run',side_effect=fake_run), contextlib.redirect_stdout(io.StringIO()):
                    result=linux_gate.host_checkpoint(evidence,work,'a'*40,green=True)
                checked.assert_called_once_with(root,service=True)
                self.assertEqual(targets,list(GREEN_CONTRACT['targets']))
                self.assertEqual(result['executed_tests'],45)
                self.assertEqual(result['accepted'],failing is None)
                self.assertEqual(result['rust_service_host_green'],failing is None)
                self.assertFalse(result['shipping_or_service_green'])
                self.assertNotIn('service_controller',result['not_run'])
                self.assertEqual(result['not_run']['service_jvm'],'NOT_RUN')
                self.assertEqual(result['not_run']['service_inverses'],'NOT_RUN')

    def test_green_mode_selects_only_host_job(self):
        for suite,ref in [('service-host-green','ignored'),('', 'lab/android-rust-bridge-service-host-green-20261015')]:
            result,output=select(suite,ref)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertEqual(output,{'mode':'service-host-green','red':'[]'})


if __name__=='__main__':
    unittest.main()
