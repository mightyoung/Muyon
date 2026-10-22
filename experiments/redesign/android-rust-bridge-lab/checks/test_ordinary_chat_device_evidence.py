"""Socket-free probes of the ordinary-chat device runner, using disposable fake tools only."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[4]
RUNNER = Path(__file__).with_name('ordinary_chat_device.sh')
PHASES = ['sdk', 'avd', 'boot', 'install', 'instrumentation', 'result']
STUB = '''#!/usr/bin/python3
import json, os, pathlib, sys
name=pathlib.Path(sys.argv[0]).name
args=sys.argv[1:]
with open(os.environ['FAKE_TRACE'], 'a') as f: f.write(json.dumps([name, args])+'\\n')
phase={'sdkmanager':'sdk', 'avdmanager':'avd', 'sudo':'avd', 'emulator':'boot'}.get(name)
if name=='timeout':
    if 'wait-for-device' in args: phase='boot'
    else: os.execvp(args[1],args[1:])
if name=='adb':
    if args[0]=='install': phase='install'
    elif 'instrument' in args: phase='instrumentation'
    else: phase='boot'
if phase==os.environ.get('FAKE_FAIL'): sys.exit(23)
if name=='adb' and 'getprop' in args: print('26' if 'ro.build.version.sdk' in args else '1')
if name=='adb' and 'instrument' in args:
    print('INSTRUMENTATION_STATUS: class=com.mightyoung.muyon.androidlab.OrdinaryChatServiceLoopTest')
    print('FAILURES!!!' if os.environ.get('FAKE_FAIL')=='result' else 'OK (2 tests)')
'''


class DeviceEvidenceTest(unittest.TestCase):
    def run_case(self, failure):
        with tempfile.TemporaryDirectory(prefix='ordinary-evidence-') as directory:
            tmp = Path(directory)
            sdk = tmp / 'sdk'
            bins = tmp / 'bin'
            bins.mkdir()
            for name in ['sdkmanager', 'avdmanager', 'emulator', 'sudo', 'adb', 'timeout']:
                path = bins / name
                path.write_text(STUB)
                path.chmod(0o755)
            for name, relative in [('sdkmanager', 'cmdline-tools/latest/bin'),
                                   ('avdmanager', 'cmdline-tools/latest/bin'),
                                   ('emulator', 'emulator')]:
                parent = sdk / relative
                parent.mkdir(parents=True, exist_ok=True)
                (parent / name).symlink_to(bins / name)
            evidence = tmp / 'chat-package'
            evidence.mkdir()
            trace = tmp / 'trace.jsonl'
            env = dict(os.environ, RUNNER_TEMP=str(tmp), ANDROID_HOME=str(sdk),
                       PATH=str(bins) + ':' + os.environ['PATH'],
                       FAKE_FAIL=failure or '', FAKE_TRACE=str(trace))
            # Before the fix, run the exact inline workflow step to demonstrate the gap.
            if RUNNER.exists():
                command = ['bash', str(RUNNER)]
            else:
                workflow = (ROOT / '.github/workflows/ordinary-chat-offline.yml').read_text()
                block = workflow.split('      - name: API26 exact Compose Service Agent ordinary chat\n')[1]
                body = block.split('        run: |\n', 1)[1].split('      - uses:', 1)[0]
                command = ['bash', '-c', '\n'.join(line[10:] for line in body.splitlines())]
            result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=10)
            phases_file = evidence / 'device-phases.tsv'
            self.assertTrue(phases_file.exists(), 'missing phase evidence after device command')
            rows = [line.split('\t') for line in phases_file.read_text().splitlines()]
            sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
            self.assertTrue(all(row[0] == sha for row in rows))
            status = (evidence / 'device-result.txt').read_text()
            calls = [json.loads(line) for line in trace.read_text().splitlines()]
            instrumented = any(name == 'adb' and 'instrument' in args for name, args in calls)
            if failure:
                self.assertNotEqual(0, result.returncode)
                self.assertEqual([sha, failure, 'FAIL', str(result.returncode)], rows[-1])
                self.assertNotIn('PASS:', status)
                if PHASES.index(failure) < PHASES.index('instrumentation'):
                    self.assertTrue(status.startswith('NOT_RUN:'), status)
                    self.assertFalse(instrumented)
                else:
                    self.assertTrue(status.startswith('NOT_VERIFIED:'), status)
                    self.assertTrue(instrumented)
            else:
                self.assertEqual(0, result.returncode, result.stderr)
                self.assertEqual(PHASES, [row[1] for row in rows if row[2] == 'PASS'])
                self.assertTrue(status.startswith('PASS:'))
            self.assertEqual(len({row[1] for row in rows if row[2] == 'START'}),
                             PHASES.index(failure) + 1 if failure else len(PHASES))

    def test_each_failure_and_success_records_its_own_terminal_evidence(self):
        for failure in PHASES + [None]:
            with self.subTest(failure=failure):
                self.run_case(failure)


if __name__ == '__main__':
    unittest.main()
