"""Synthetic classifier controls, never actual mapper execution evidence."""
import unittest
import contextlib
import hashlib
import io
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
from unittest.mock import patch
import mapper_control_green
from mapper_control_green import CONTRACT, SUMMARY, classify
from test_mapper_control import transcript as old_red

SOURCE = CONTRACT['author_commit']
LIBRARY = 'b' * 64


def transcript():
    return '\n'.join([f'AGENT_MAPPER_JVM_MAPPED source={SOURCE} sha256={LIBRARY}'] +
        ['PASS B generated projection ' + name for name in CONTRACT['case_names']] + [SUMMARY]) + '\n'


class MapperGreenControls(unittest.TestCase):
    def test_all_six_named_passes_exact_header_summary_exit_zero(self):
        raw = transcript()
        self.assertTrue(classify(raw, 0, SOURCE, LIBRARY)['accepted'])
        for bad in [raw+raw, raw.replace(SUMMARY, ''), raw.replace(CONTRACT['case_names'][5], 'unknown'), old_red(), raw.replace(SOURCE, 'a'*40)]:
            self.assertFalse(classify(bad, 0, SOURCE, LIBRARY)['accepted'])
        for name in CONTRACT['case_names']:
            self.assertFalse(classify(raw.replace('PASS B generated projection '+name+'\n', ''), 0, SOURCE, LIBRARY)['accepted'])
        lines=raw.splitlines();lines[1],lines[2]=lines[2],lines[1]
        self.assertFalse(classify('\n'.join(lines), 0, SOURCE, LIBRARY)['accepted'])
        for status in [1,101,124,-6,-9]:
            self.assertFalse(classify(raw, status, SOURCE, LIBRARY)['accepted'])

    def test_wrong_source_or_library_pin_cannot_accept_a_matching_transcript(self):
        for source in ['a'*40, '', SOURCE+'0']:
            self.assertFalse(classify(transcript().replace(SOURCE, source), 0, source, LIBRARY)['accepted'])
        for library in ['', 'b'*63, 'B'*64]:
            self.assertFalse(classify(transcript().replace(LIBRARY, library), 0, SOURCE, library)['accepted'])

    def test_generation_runs_in_bridge_core_and_records_command_status(self):
        # Synthetic subprocesses isolate orchestration; never actual JVM GREEN.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)/'source'; root.mkdir()
            core = root/'experiments/redesign/android-rust-bridge-lab/core'; core.mkdir(parents=True)
            (core/'uniffi.jvm.toml').write_text('synthetic config')
            files = {}
            for name in ['library', 'jna', 'bindgen', 'kotlinc']:
                files[name] = Path(tmp)/name; files[name].write_text(name)
            evidence = Path(tmp)/'evidence'; observed = []
            actual_sha256 = hashlib.sha256
            def digest(data):
                if data == b'jna':
                    return SimpleNamespace(hexdigest=lambda: '4fb141dd8ef6b0585ffceea4bc49602fbc6312fa977e2c488794ea3e6aafecae')
                return actual_sha256(data)
            def run(command, *, cwd, stdout, stderr, timeout):
                observed.append((command, Path(cwd)))
                if command[:2] == ['java', '-version']:
                    stdout.write('openjdk version "17.0.1"\n')
                elif command[1:] == ['-version']:
                    stdout.write('kotlinc-jvm 2.2.20\n')
                elif command[1] == 'generate':
                    self.assertEqual(Path(cwd), core)
                    binding = evidence/'fresh-jvm/com/mightyoung/muyon/androidbridge/muyon_android_contract_bridge.kt'
                    binding.parent.mkdir(parents=True); binding.write_text('// synthetic binding')
                elif '-include-runtime' in command:
                    Path(command[-1]).write_text('synthetic jar')
                else:
                    library_sha = actual_sha256(b'library').hexdigest()
                    stdout.write(transcript().replace(LIBRARY, library_sha))
                return SimpleNamespace(returncode=0)
            arguments = ['mapper_control_green.py', '--source-root', str(root), '--evidence-dir', str(evidence)]
            for name, path in files.items(): arguments += ['--'+name, str(path)]
            with patch('sys.argv', arguments), patch('subprocess.check_output', return_value=SOURCE), \
                    patch('subprocess.run', side_effect=run), patch.object(mapper_control_green, 'inventory'), \
                    patch.object(mapper_control_green.hashlib, 'sha256', side_effect=digest), contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaises(SystemExit) as stopped: mapper_control_green.main()
            self.assertEqual(stopped.exception.code, 0)
            records = json.loads((evidence/'provenance.json').read_text())['commands']
            self.assertEqual(len(records), len(observed))
            for record, (command, cwd) in zip(records, observed):
                self.assertEqual(record['command'], command)
                self.assertEqual(record['cwd'], str(cwd))
                self.assertEqual(record['exit_code'], 0)
                self.assertFalse(record['timed_out'])
            self.assertEqual([cwd for command,cwd in observed if command[1] != 'generate'], [root]*4)

    def test_any_mixed_load_fault_or_extra_mapping_header_remains_invalid(self):
        raw=transcript()
        for extra in ['UnsatisfiedLinkError: missing native library', 'NoClassDefFoundError: generated record class',
            'NoSuchMethodError: incompatible generated type', 'checksum mismatch: generated contract',
            'ClassNotFoundException: generated record class', 'ExceptionInInitializerError: incompatible binding',
            'LinkageError: incompatible native component', 'UnsupportedClassVersionError: incompatible compiler',
            'AGENT_MAPPER_JVM_MAPPED malformed extra header', 'Exception in thread "main" java.lang.IllegalStateException: other',
            "thread 'worker' panicked at setup.rs:1:1:"]:
            for bad in [extra+'\n'+raw, raw+extra+'\n']:
                self.assertFalse(classify(bad, 0, SOURCE, LIBRARY)['accepted'])


if __name__=='__main__':
    unittest.main()
