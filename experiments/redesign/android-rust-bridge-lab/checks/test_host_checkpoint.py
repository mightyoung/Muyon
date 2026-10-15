"""Checkpoint helper controls; these are not actual host tests."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from host_checkpoint import inventory, target_green, CONTRACT, oracle_inventory, oracle_red, ORACLE
from test_workflow_selection import select


def transcript(target):
    names = CONTRACT['targets'][target]['names']
    return ('Finished `release` profile [optimized]\n'
        + f'Running tests/{target}.rs (target/release/deps/{target}-abc)\n'
        + '\n'.join(f'test {name} ... ok' for name in names)
        + f'\ntest result: ok. {len(names)} passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.01s\n')


def oracle_transcript():
    red = ORACLE['red']; target = red['target']; name = red['test']
    return (f"Finished `release` profile [optimized]\nRunning tests/{target}.rs (target/release/deps/{target}-abc)\n"
               + red['native_reach'] + "\nthread '" + name + "' (901) panicked at tests/service_oracle.rs:101:9:\n"
               + red['rust_assert'] + f"\ntest {name} ... FAILED\ntest result: FAILED. 0 passed; 1 failed; 0 ignored; 0 measured; 0 filtered out;\n")


class HostCheckpointControls(unittest.TestCase):
    def test_each_target_requires_all_exact_names_and_clean_exit(self):
        self.assertEqual({key: len(v['names']) for key, v in CONTRACT['targets'].items()},
                         dict(native_read=25, contract_transport=8, service_runtime=2, service_root=2))
        self.assertEqual(len(CONTRACT['not_run']['service_controller']['names']), 4)
        for target, group in CONTRACT['targets'].items():
            raw = transcript(target)
            self.assertTrue(target_green(target, raw, 0)['accepted'])
            for bad in [raw + raw, raw.replace(group['names'][0], 'unexpected'),
                        raw.replace(' ... ok', ' ... FAILED', 1),
                        raw.replace('0 ignored', '1 ignored'), raw.replace('0 filtered', '1 filtered'),
                        raw.replace('0 measured', '1 measured'), raw.replace('Finished', 'Compiling'),
                        raw.replace(f'Running tests/{target}.rs', 'Running tests/service_controller.rs'),
                        raw + '\ntest unknown ... ok\n', raw + '\nerror[E0000]: compilation failure\n']:
                self.assertFalse(target_green(target, bad, 0)['accepted'])
            for status in [1, 101, 124, -6, -9]:
                self.assertFalse(target_green(target, raw, status)['accepted'])
        self.assertFalse(target_green('service_controller', transcript('service_root'), 0)['accepted'])

    def test_inventory_checks_source_blobs_names_and_not_run_source(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            contract = copy.deepcopy(CONTRACT)
            import hashlib
            for groups in [contract['targets'], contract['not_run']]:
                for target, group in groups.items():
                    data = ('\n'.join('#[test]\nfn '+name+'() {}' for name in group['names'])).encode()
                    path = root / group['path']; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(data)
                    group['sha256'] = hashlib.sha256(data).hexdigest()
                    group['blob_sha'] = hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()
            self.assertEqual(inventory(root, contract), contract)
            for target in ['native_read', 'service_controller']:
                group = (contract['targets'] | contract['not_run'])[target]
                path = root / group['path']; before = path.read_bytes(); path.write_bytes(before+b'\n')
                with self.assertRaisesRegex(RuntimeError, 'host_checkpoint_inventory_invalid'):
                    inventory(root, contract)
                path.write_bytes(before)
            invalid = copy.deepcopy(contract); invalid['targets']['unknown'] = invalid['targets']['service_root']
            with self.assertRaisesRegex(RuntimeError, 'host_checkpoint_inventory_invalid'):
                inventory(root, invalid)

    def test_orchestration_runs_all_four_targets_without_bridge_or_jvm(self):
        import contextlib
        import io
        from unittest.mock import patch
        import linux_gate
        for fail_first, oracle in [(False, False), (True, False), (False, True), (True, True)]:
            with tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp); evidence = root / 'evidence'; evidence.mkdir()
                work = root / 'work'; work.mkdir()
                host = root / CONTRACT['manifest']; host.parent.mkdir(parents=True)
                (host.parent / 'Cargo.lock').write_text('fixed zero-external-dependency lock')
                calls = []
                def fake_run(command, log, env, **kwargs):
                    words = [str(x) for x in command]; calls.append(words)
                    text = ''
                    status = 0
                    if words == ['rustc', '--version']:
                        text = 'rustc 1.99.0 (synthetic helper control)\n'
                    elif '--bin' in words:
                        binary = work / 'host-target/release/muyon-plugin-contract-lab'
                        binary.parent.mkdir(parents=True); binary.write_bytes(b'control binary')
                    elif '--test' in words:
                        target = words[words.index('--test') + 1]
                        text = oracle_transcript() if target == 'service_oracle' else transcript(target)
                        if target == 'service_oracle':
                            status = 101
                        self.assertEqual(env['MUYON_PLUGIN_CONTRACT_BIN'], str(work / 'host-target/release/muyon-plugin-contract-lab'))
                        if fail_first and target == 'native_read':
                            text = text.replace(' ... ok', ' ... FAILED', 1); status = 101
                    log.write_text(text)
                    return status
                with patch.object(linux_gate, 'ROOT', root), patch.object(linux_gate, 'checkpoint_inventory', return_value=CONTRACT), patch.object(linux_gate, 'oracle_inventory', return_value=ORACLE), patch.object(linux_gate, 'run', side_effect=fake_run), contextlib.redirect_stdout(io.StringIO()):
                    result = linux_gate.host_checkpoint(evidence, work, 'a' * 40, oracle=oracle)
                self.assertEqual(result['accepted'], not fail_first)
                self.assertFalse(result['shipping_or_service_green'])
                self.assertEqual([row['target'] for row in result['targets']], list(CONTRACT['targets']))
                self.assertEqual(result['executed_tests'], 37)
                self.assertIn('initial refusal', result['not_run']['service_controller'])
                self.assertEqual([words[words.index('--test')+1] for words in calls if '--test' in words],
                                 list(CONTRACT['targets']) + (['service_oracle'] if oracle and not fail_first else []))
                if oracle and not fail_first:
                    self.assertEqual(result['command_exit_code'], 101)
                    self.assertEqual(result['classification'], 'semantic_red')
                if oracle and fail_first:
                    self.assertEqual(result['oracle']['classification'], 'NOT_RUN')
                self.assertIn(['cargo', 'test', '--offline', '--locked', '--release', '--no-run'], calls)
                self.assertFalse(any('bindings' in words or 'java' in words or 'uniffi-bindgen' in words for words in calls))

    def test_oracle_red_requires_unique_source_bound_reach_and_precise_failure(self):
        red = ORACLE['red']; target = red['target']; name = red['test']
        raw = oracle_transcript()
        self.assertTrue(oracle_red(raw, 101, 'a' * 40, '0' * 64)['accepted'])
        for bad in [raw.replace(red['native_reach'], ''), raw + raw,
                    raw.replace(red['rust_assert'], 'unrelated setup fault'),
                    raw.replace(name, 'unknown_case'), raw.replace('0 filtered', '1 filtered'),
                    raw.replace('0 ignored', '1 ignored'), raw.replace('Finished', 'Compiling'),
                    raw.replace(red['native_reach']+'\n', '') + red['native_reach'],
                    raw + "thread 'other' panicked at tests/setup.rs:1:1:\nsetup\n",
                    raw + '\nerror[E0000]: compilation failure\n']:
            self.assertFalse(oracle_red(bad, 101, 'a' * 40, '0' * 64)['accepted'])
        for status in [0, 1, 124, -6, -9]:
            self.assertFalse(oracle_red(raw, status, 'a' * 40, '0' * 64)['accepted'])
        self.assertEqual(oracle_red(raw, 101, 'a' * 40, '0' * 64)['scope'], 'controller entry/refusal only; worker/observer execution not reached')
        import hashlib
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); contract=copy.deepcopy(ORACLE)
            path=root/contract['path'];path.parent.mkdir(parents=True)
            data=('#[test]\nfn '+name+'() {}').encode();path.write_bytes(data)
            contract['sha256']=hashlib.sha256(data).hexdigest()
            contract['blob_sha']=hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()
            self.assertEqual(oracle_inventory(root,contract),contract)
            path.write_bytes(data+b'\n')
            with self.assertRaisesRegex(RuntimeError,'service_oracle_inventory_invalid'):
                oracle_inventory(root,contract)
        for suite,ref in [('service-oracle-red','ignored'),('', 'lab/android-rust-bridge-service-oracle-red-20261015')]:
            result,output=select(suite,ref)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertEqual(output,{'mode':'service-oracle-red','red':'[]'})

    def test_main_preserves_required_red_nonzero_after_recognition(self):
        import contextlib
        import io
        from unittest.mock import patch
        import linux_gate
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            arguments = ['linux_gate.py', '--mode', 'service-oracle-red',
                         '--evidence-dir', str(root / 'evidence'), '--work-dir', str(root / 'work')]
            recognized = dict(accepted=True, classification='semantic_red', command_exit_code=101,
                              shipping_or_service_green=False)
            with patch('sys.argv', arguments), patch.object(linux_gate, 'tracked_inputs', return_value={}), patch.object(linux_gate.subprocess, 'check_output', side_effect=['a' * 40, b'']), patch.object(linux_gate, 'host_checkpoint', return_value=recognized), contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(linux_gate.main(), 101)
            verdict = json.loads((root / 'evidence/verdict.json').read_text())
            self.assertTrue(verdict['accepted'])
            self.assertEqual(verdict['command_exit_code'], 101)
            self.assertFalse(verdict['shipping_or_service_green'])

    def test_explicit_and_named_checkpoint_route_without_full_or_red(self):
        for suite, ref in [('service-host-checkpoint', 'ignored'),
                           ('', 'lab/android-rust-bridge-service-host-checkpoint-20261015')]:
            result, output = select(suite, ref)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(output, {'mode': 'service-host-checkpoint', 'red': '[]'})


if __name__ == '__main__':
    unittest.main()
